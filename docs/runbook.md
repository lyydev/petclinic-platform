# Operational Runbook — CI/CD OIDC, GitOps Image Updates, and Rollbacks

**Last Updated:** 2026-10-30  
**Purpose:** Provide day-to-day operational procedures and incident troubleshooting for GitHub Actions AWS OIDC federation, ARM64 CI build & Trivy vulnerability scanning, the GitOps image-tag pipeline, and deployment rollbacks across `dev` and `prod` (Stories: PETPLAT-49, PETPLAT-50, PETPLAT-52, PETPLAT-53, PETPLAT-54, PETPLAT-87, PETPLAT-105).

---

## Table of Contents

1. [CI/CD & GitOps Architecture](#1-cicd--gitops-architecture)
2. [AWS OIDC Federation & GitHub Secrets Setup](#2-aws-oidc-federation--github-secrets-setup)
   - [Procedure: Provision OIDC Federation and Configure GitHub Secrets](#procedure-provision-oidc-federation-and-configure-github-secrets)
3. [GitOps Image Tag Update Mechanism](#3-gitops-image-tag-update-mechanism)
   - [Procedure: Trigger or Re-run Image Tag Update Manually](#procedure-trigger-or-re-run-image-tag-update-manually)
4. [Rollback Strategy & Operational Procedures](#4-rollback-strategy--operational-procedures)
   - [Procedure: GitOps Rollback via Git Revert (Primary)](#procedure-gitops-rollback-via-git-revert-primary)
   - [Procedure: ArgoCD CLI / UI Rollback (Production Manual-Sync)](#procedure-argocd-cli--ui-rollback-production-manual-sync)
   - [Procedure: Emergency Fallback via kubectl rollout undo](#procedure-emergency-fallback-via-kubectl-rollout-undo)
   - [Procedure: End-to-End Rollback Verification Drill](#procedure-end-to-end-rollback-verification-drill)
5. [Troubleshooting & Incident Response](#5-troubleshooting--incident-response)
   - [Incident: OIDC AssumeRoleWithWebIdentity Fails (403 AccessDenied)](#incident-oidc-assumerolewithwebidentity-fails-403-accessdenied)
   - [Incident: Image Tag Update Workflow Fails or Rejects Payload](#incident-image-tag-update-workflow-fails-or-rejects-payload)
   - [Incident: Pod CrashLoopBackOff After Rollback](#incident-pod-crashloopbackoff-after-rollback)
6. [CI Vulnerability Scanning & Trivy Allowlist](#6-ci-vulnerability-scanning--trivy-allowlist)
   - [Procedure: Review Trivy Scan Results and Add Accepted CVEs to Allowlist](#procedure-review-trivy-scan-results-and-add-accepted-cves-to-allowlist)

---

## 1. CI/CD & GitOps Architecture

GitHub Actions handles **CI only**; ArgoCD handles **CD** (see [ADR-0005](./technical-spec.md#adr-index) and [ADR-0008](./technical-spec.md#adr-index)):

```text
Push to lyydev/spring-petclinic-microservices (main)
  └── build-push.yml (App Repo)
        ├── Assumes petclinic-dev-github-actions-role via OIDC (sts:AssumeRoleWithWebIdentity)
        ├── Builds linux/arm64 images, scans with Trivy, pushes 7-char SHA tags to ECR
        └── Fires repository_dispatch (type: app-image-built) to petclinic-platform
              │
              ▼
  └── .github/workflows/update-image-tags.yml (Platform Repo)
        ├── Updates .image.tag in helm-values/{service}.yaml via yq
        ├── Lints Helm charts across dev & prod values
        └── Commits & pushes "ci: update image tags to <sha> (<services>)" to main
              │
              ▼
  └── ArgoCD (In-Cluster on EKS)
        ├── petclinic-dev: Automated sync (prune + selfHeal) deploys immediately
        └── petclinic-prod: Marks OutOfSync; awaits manual operator approval
```

---

## 2. AWS OIDC Federation & GitHub Secrets Setup

Terraform module `terraform/modules/github-oidc/` provisions keyless authentication between GitHub Actions and AWS IAM:
- **OIDC Provider:** `https://token.actions.githubusercontent.com` (audience `sts.amazonaws.com`)
- **Trusted Subject (`StringEquals`):** `repo:lyydev/spring-petclinic-microservices:ref:refs/heads/main` (strictly scoped to the application repository fork `main` branch — never `*`, never the platform repo)
- **Assume-Role Action:** `sts:AssumeRoleWithWebIdentity` (`max_session_duration = 3600`)
- **IAM Permissions:** Least-privilege ECR push only (`ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage` scoped to explicit `module.ecr.repository_arns`)
- **Environment Variants (Single AWS Account):**
  - `terraform/environments/dev`: Creates the account-level IAM OIDC provider (`create_github_oidc_provider = true`) and `petclinic-dev-github-actions-role` scoped to `petclinic-dev/*` ECR repositories. Apply `dev` first in a shared AWS account.
  - `terraform/environments/prod`: Reuses the account-level IAM OIDC provider (`create_github_oidc_provider = false`, override to `true` only if `prod` runs in a separate AWS account) and creates `petclinic-prod-github-actions-role` scoped to `petclinic-prod/*` ECR repositories.

### Required GitHub Secrets

Configure the following repository secrets in the **application repository fork** (`lyydev/spring-petclinic-microservices` → *Settings → Secrets and variables → Actions*):

| Secret Name | Where Used | Example / Source |
|-------------|------------|------------------|
| `AWS_REGION` | `build-push.yml` | `us-east-1` |
| `AWS_ACCOUNT_ID` | `build-push.yml` | Output of `aws sts get-caller-identity --query Account --output text` |
| `AWS_ROLE_ARN` | `build-push.yml` (`aws-actions/configure-aws-credentials`) | `terraform -chdir=terraform/environments/dev output -raw github_actions_role_arn` |
| `PLATFORM_REPO_TOKEN` | `build-push.yml` (`repository_dispatch` trigger) | Fine-grained GitHub PAT scoped to `lyydev/petclinic-platform` with `Contents: Read and write` |

> **Note:** The platform repository (`petclinic-platform`) requires **zero AWS credentials** because `.github/workflows/update-image-tags.yml` only edits `helm-values/*.yaml` and pushes to Git using the built-in `GITHUB_TOKEN` (`permissions: contents: write`).

### Procedure: Provision OIDC Federation and Configure GitHub Secrets

**When:** Initial CI/CD setup or onboarding a new AWS environment.  
**Who:** Platform engineer with AWS IAM admin and GitHub repository admin access.  
**Time:** ~10 minutes.

**Steps:**
1. From the `petclinic-platform` repository root, plan and apply `terraform/environments/dev/` (and optionally `prod` afterward):
   ```bash
   terraform -chdir=terraform/environments/dev init
   terraform -chdir=terraform/environments/dev validate
   terraform -chdir=terraform/environments/dev plan -out=plan.out
   terraform -chdir=terraform/environments/dev apply plan.out
   ```
2. Retrieve the federated IAM role ARN and AWS account ID from the repository root:
   ```bash
   ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw github_actions_role_arn)
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   ```
3. Set the GitHub Actions secrets on `lyydev/spring-petclinic-microservices` using the GitHub CLI:
   ```bash
   gh secret set AWS_REGION --repo lyydev/spring-petclinic-microservices --body "us-east-1"
   gh secret set AWS_ACCOUNT_ID --repo lyydev/spring-petclinic-microservices --body "${ACCOUNT_ID}"
   gh secret set AWS_ROLE_ARN --repo lyydev/spring-petclinic-microservices --body "${ROLE_ARN}"
   ```
4. Export a fine-grained Personal Access Token scoped solely to `petclinic-platform` (`Contents: Read and write`) into `PLATFORM_REPO_TOKEN` in your local shell and upload it non-interactively:
   ```bash
   printf '%s' "${PLATFORM_REPO_TOKEN}" | gh secret set PLATFORM_REPO_TOKEN --repo lyydev/spring-petclinic-microservices
   ```

**Verify:**
- Confirm the IAM role trust policy in AWS:
  ```bash
  aws iam get-role --role-name petclinic-dev-github-actions-role \
    --query 'Role.AssumeRolePolicyDocument' --output json
  ```
- Expected output:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "GitHubActionsOIDCAssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::037547369073:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
            "token.actions.githubusercontent.com:sub": "repo:lyydev/spring-petclinic-microservices:ref:refs/heads/main"
          }
        }
      }
    ]
  }
  ```

**Rollback:**
- Remove the GitHub secrets via `gh secret delete <NAME> --repo lyydev/spring-petclinic-microservices` and revert the Terraform module change via saved plan if needed.

---

## 3. GitOps Image Tag Update Mechanism

### Why `yq` Was Chosen (`PETPLAT-87`)

`mikefarah/yq` v4 was selected over `sed` or regex text replacement because:
1. **AST-aware YAML editing:** Preserves comments, indentation, and structure in `helm-values/{service}.yaml`.
2. **Type safety:** Using `IMAGE_TAG="${SHORT_SHA}" yq -i '.image.tag = strenv(IMAGE_TAG) | .image.tag style="double"'` guarantees all-numeric or hex-exponent commit SHAs (e.g., `635e812`, `1234567`) remain quoted YAML strings rather than floats or integers.
3. **Injection safety:** Reading `IMAGE_TAG` from environment variables via `strenv()` prevents YAML/command injection from dispatch payloads.

### Payload Contract (`repository_dispatch` type `app-image-built`)

- **Update all 8 services:**
  ```json
  {
    "event_type": "app-image-built",
    "client_payload": {
      "sha": "635f8be"
    }
  }
  ```
- **Update specific changed services:**
  ```json
  {
    "event_type": "app-image-built",
    "client_payload": {
      "sha": "635f8be",
      "services": "customers-service visits-service"
    }
  }
  ```

### Procedure: Trigger or Re-run Image Tag Update Manually

**When:** Re-dispatching an image tag update after a transient GitHub outage or promoting a verified ECR image SHA.  
**Who:** Platform engineer or on-call engineer.  
**Time:** ~2 minutes.

**Steps:**
1. Verify the target `<sha>` tag exists in ECR before dispatching:
   ```bash
   aws ecr describe-images \
     --repository-name petclinic-dev/customers-service \
     --image-ids imageTag=635f8be \
     --region us-east-1
   ```
2. Dispatch the `app-image-built` event to the platform repository using raw JSON input:
   ```bash
   gh api repos/lyydev/petclinic-platform/dispatches \
     --method POST \
     --input - <<< '{"event_type": "app-image-built", "client_payload": {"sha": "635f8be", "services": "all"}}'
   ```

**Verify:**
- Watch the workflow run and inspect the resulting commit on `main`:
  ```bash
  gh run list --repo lyydev/petclinic-platform --workflow update-image-tags.yml --limit 1
  git pull origin main && git log -n 1 --stat
  ```
- Expected output:
  ```text
  STATUS     TITLE               WORKFLOW           BRANCH  EVENT                ID
  completed  app-image-built     Update Image Tags  main    repository_dispatch  12345678901

  commit a1b2c3d4e5f6...
  Author: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>
      ci: update image tags to 635f8be (config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server)
   8 files changed, 8 insertions(+), 8 deletions(-)
  ```

**Rollback:**
- Follow [Procedure: GitOps Rollback via Git Revert](#procedure-gitops-rollback-via-git-revert-primary).

---

## 4. Rollback Strategy & Operational Procedures

Choose the rollback tier based on urgency and environment (`PETPLAT-54`):

| Tier | Mechanism | Best For | Preserves GitOps Single Source of Truth? |
|------|-----------|----------|------------------------------------------|
| **1 (Primary)** | Git revert / tag pin (`./scripts/rollback.sh --strategy gitops`) | All `dev` and `prod` rollbacks | **Yes** — Git commit triggers ArgoCD |
| **2 (Secondary)** | ArgoCD rollback (`argocd app rollback`) | Rapid `prod` rollback (manual sync) | Temporary until Git is also reverted |
| **3 (Emergency)** | Kubernetes rollout undo (`kubectl rollout undo`) | Control-plane / ArgoCD outage during SEV1 | No — must follow up with Tier 1 Git revert |

### Common `scripts/rollback.sh` Safety Flags
- `--dry-run`: Prints exact `git`, `yq`, `argocd`, or `kubectl` commands without mutating Git, ArgoCD, or Kubernetes. Always run with `--dry-run` first when time permits.
- `--yes`: Confirms production rollbacks (or pushes to shared `origin/main` `helm-values/`) non-interactively during automated runbooks. Without `--yes`, `scripts/rollback.sh` prompts interactively before mutating `prod` or pushing to `origin/main`.

---

### Procedure: GitOps Rollback via Git Revert (Primary)

**When:** A newly deployed image tag introduces errors, crash loops, or latency regressions in `dev` or `prod`.  
**Who:** On-call engineer or platform engineer.  
**Time:** ~3–5 minutes.

**Steps:**
1. Identify the offending `ci: update image tags...` commit in `petclinic-platform`:
   ```bash
   git log --oneline -n 5 -- helm-values/
   ```
2. Preview the rollback with `--dry-run`, then execute and push:
   ```bash
   ./scripts/rollback.sh --strategy gitops --commit <bad-commit-sha> --dry-run
   ./scripts/rollback.sh --strategy gitops --commit <bad-commit-sha> --push
   ```
   *(Alternatively, pin a single service to a known-good SHA: `./scripts/rollback.sh --strategy gitops --service customers-service --tag 635f8be --push`)*
3. Wait for ArgoCD to reconcile:
   - **Dev (`petclinic-dev`):** Auto-sync reconciles automatically within ~3 minutes (or force immediate sync via `argocd app sync -l environment=dev`).
   - **Prod (`petclinic-prod`):** Approve the sync explicitly:
     ```bash
     argocd app diff customers-service-prod || true
     argocd app sync customers-service-prod
     argocd app wait customers-service-prod --health --timeout 180
     ```

**Verify:**
- Confirm running pod images and health probes (shown for `petclinic-dev`; substitute `petclinic-prod` for production):
  ```bash
  kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=customers-service \
    -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.containers[0].image
  ```
- Expected output:
  ```text
  NAME                                 STATUS    IMAGE
  customers-service-6b7f8c9d4b-x9k2m   Running   037547369073.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/customers-service:635f8be
  ```

**Rollback:**
- Revert the revert commit (`git revert --no-edit HEAD && git push origin main`) if the rollback targeted the wrong commit.

---

### Procedure: ArgoCD CLI / UI Rollback (Production Manual-Sync)

**When:** Immediate rollback of a `petclinic-prod` application to its prior ArgoCD sync revision while a Git PR is being prepared.  
**Who:** Platform admin (`admin` role in `argocd-rbac-cm`).  
**Time:** ~2 minutes.

> **Important:** In `petclinic-dev`, `automated.selfHeal: true` is active — ArgoCD will block or revert out-of-band rollbacks unless auto-sync is disabled first. Always prefer Tier 1 (`git revert`) for `dev`.

**Steps:**
1. Inspect deployment sync history for the affected `prod` application:
   ```bash
   argocd app history customers-service-prod
   ```
2. Preview with `--dry-run`, then roll back to the previous healthy numeric `<history-id>`:
   ```bash
   ./scripts/rollback.sh --strategy argocd --env prod --service customers-service --revision <history-id> --dry-run
   ./scripts/rollback.sh --strategy argocd --env prod --service customers-service --revision <history-id>
   ```
3. Immediately commit the matching `image.tag` revert to `helm-values/customers-service.yaml` in Git so future syncs remain aligned.

**Verify:**
- Check ArgoCD health and pod readiness in `petclinic-prod`:
  ```bash
  argocd app get customers-service-prod
  kubectl rollout status deployment/customers-service -n petclinic-prod --timeout=120s
  ```
- Expected output:
  ```text
  Health Status:      Healthy
  Sync Status:        OutOfSync (until matching Git revert is merged)
  deployment "customers-service" successfully rolled out
  ```

**Rollback:**
- Re-sync to `HEAD` (`argocd app sync customers-service-prod`) once fixed in Git.

---

### Procedure: Emergency Fallback via kubectl rollout undo

**When:** SEV1 production outage where GitHub or ArgoCD is unavailable/unresponsive.  
**Who:** On-call engineer with EKS cluster access.  
**Time:** ~1–2 minutes.

**Steps:**
1. If ArgoCD is reachable and rolling back `dev`, suspend auto-sync temporarily so `selfHeal` does not undo the emergency rollback:
   ```bash
   argocd app set customers-service-dev --sync-policy none
   ```
2. Inspect Kubernetes Deployment revision history (use `-n petclinic-dev` or `-n petclinic-prod`):
   ```bash
   kubectl rollout history deployment/customers-service -n petclinic-prod
   ```
3. Execute `kubectl rollout undo` (for `--service all`, `scripts/rollback.sh` automatically rolls back in reverse dependency order: domain/edge services → `discovery-server` → `config-server`):
   ```bash
   ./scripts/rollback.sh --strategy kubectl --env prod --service customers-service
   ```
4. Once GitHub/ArgoCD access is restored, revert `helm-values/` in Git and re-enable ArgoCD auto-sync on `dev` (`argocd app set customers-service-dev --sync-policy automated --auto-prune --self-heal`).

**Verify:**
- Confirm pods are `Running` and `1/1` Ready:
  ```bash
  kubectl get pods -l app.kubernetes.io/name=customers-service -n petclinic-prod
  ```
- Expected output:
  ```text
  NAME                                 READY   STATUS    RESTARTS   AGE
  customers-service-6b7f8c9d4b-p4m8q   1/1     Running   0          45s
  customers-service-6b7f8c9d4b-z2w7n   1/1     Running   0          62s
  ```

**Rollback:**
- Run `kubectl rollout undo deployment/customers-service -n petclinic-prod --to-revision=<N>` to return to a specific ReplicaSet revision.

---

### Procedure: End-to-End Rollback Verification Drill

**When:** Validating rollback readiness in `petclinic-dev` (`PETPLAT-54` acceptance test).  
**Who:** Platform engineer.  
**Time:** ~10 minutes.

**Steps:**
1. Record the currently healthy `customers-service` image tag and pod status in `petclinic-dev`:
   ```bash
   yq '.image.tag' helm-values/customers-service.yaml
   kubectl get pods -l app.kubernetes.io/name=customers-service -n petclinic-dev
   ```
2. Commit and push an intentionally non-existent SHA tag (e.g., `bad0000`) to `helm-values/customers-service.yaml`:
   ```bash
   yq -i '.image.tag = "bad0000" | .image.tag style="double"' helm-values/customers-service.yaml
   git add helm-values/customers-service.yaml
   git commit -m "test: simulate bad image deployment (bad0000)"
   git push origin main
   ```
3. Observe ArgoCD auto-syncing `customers-service-dev` and Kubernetes keeping the old pod alive while the new ReplicaSet enters `ImagePullBackOff` / `ErrImagePull`:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=customers-service -n petclinic-dev -w
   ```
4. Execute GitOps rollback by reverting `HEAD`:
   ```bash
   ./scripts/rollback.sh --strategy gitops --commit HEAD --yes --push
   ```

**Verify:**
- Confirm ArgoCD syncs the reverted commit, terminates the broken ReplicaSet, and reports `Synced` + `Healthy`:
  ```bash
  argocd app wait customers-service-dev --sync --health --timeout 180
  kubectl rollout status deployment/customers-service -n petclinic-dev --timeout=120s
  ```
- Expected output:
  ```text
  Name:               argocd/customers-service-dev
  Sync Status:        Synced to main
  Health Status:      Healthy
  deployment "customers-service" successfully rolled out
  ```

**Rollback:**
- Test drill runs in `petclinic-dev` only; `git log -n 2` confirms repository state is restored to the original tag.

---

## 5. Troubleshooting & Incident Response

### Incident: OIDC AssumeRoleWithWebIdentity Fails (403 AccessDenied)

**Symptoms:**
- `build-push.yml` in `lyydev/spring-petclinic-microservices` fails at `aws-actions/configure-aws-credentials` with `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`.

**Diagnosis:**
1. Inspect the workflow run's git ref — non-`main` branches or pull requests produce a different OIDC `sub` claim than `repo:lyydev/spring-petclinic-microservices:ref:refs/heads/main`.
2. Inspect the IAM role trust policy and OIDC provider thumbprints in AWS:
   ```bash
   aws iam get-role --role-name petclinic-dev-github-actions-role --query 'Role.AssumeRolePolicyDocument'
   aws iam list-open-id-connect-providers
   ```

**Resolution:**
1. Ensure the build workflow is running on `refs/heads/main` in `lyydev/spring-petclinic-microservices` with `permissions: id-token: write`.
2. Verify `AWS_ROLE_ARN` in GitHub Secrets matches `terraform -chdir=terraform/environments/dev output -raw github_actions_role_arn`.
3. Re-plan and apply `terraform/environments/dev` if IAM drift occurred.

**Escalation:**
- Escalate to the Cloud / IAM Administrator if account-level SCPs or IAM permission boundaries block `sts:AssumeRoleWithWebIdentity`.

---

### Incident: Image Tag Update Workflow Fails or Rejects Payload

**Symptoms:**
- Images push to ECR cleanly in `lyydev/spring-petclinic-microservices`, but `helm-values/*.yaml` in `petclinic-platform` is never updated or `Update Image Tags` shows `failure`.

**Diagnosis:**
1. Check recent runs and logs of `update-image-tags.yml`:
   ```bash
   gh run list --repo lyydev/petclinic-platform --workflow update-image-tags.yml --limit 5
   gh run view <run-id> --repo lyydev/petclinic-platform --log-failed
   ```
2. Common causes:
   - Expired or under-scoped `PLATFORM_REPO_TOKEN` secret on `lyydev/spring-petclinic-microservices` (no workflow run appears at all).
   - Invalid SHA (`latest` or non-hex string) or unknown service name in `client_payload`.
   - Helm lint failure caused by malformed edits in `helm-values/`.

**Resolution:**
1. Rotate `PLATFORM_REPO_TOKEN` if expired (`Contents: Read and write` on `lyydev/petclinic-platform`).
2. Re-dispatch manually with a verified 7-char ECR commit SHA using [Procedure: Trigger or Re-run Image Tag Update Manually](#procedure-trigger-or-re-run-image-tag-update-manually).

**Escalation:**
- Escalate to the Platform Engineer owning CI/CD pipelines.

---

### Incident: Pod CrashLoopBackOff After Rollback

**Symptoms:**
- `scripts/rollback.sh` completes, ArgoCD deploys the previous image SHA, and `ImagePullBackOff` clears, but pods enter `CrashLoopBackOff` or fail `/actuator/health/readiness`.

**Diagnosis:**
1. Inspect container startup logs and Kubernetes events:
   ```bash
   kubectl logs deployment/customers-service -n petclinic-dev --previous --tail=100
   kubectl describe pod -l app.kubernetes.io/name=customers-service -n petclinic-dev
   ```
2. Check whether `config-server` (`8888`) and `discovery-server` (`8761`) are healthy, or whether a forward-only Flyway/Liquibase/MySQL schema change in RDS broke backward compatibility with the older image.

**Resolution:**
1. If `config-server` or `discovery-server` is unhealthy, restore them first before restarting downstream services.
2. If caused by an incompatible RDS schema change, apply a forward-fix commit or restore RDS from snapshot per database recovery procedures rather than rolling back application code alone.

**Escalation:**
- Escalate to the Platform Lead and Application Tech Lead for coordinated database/schema remediation.

---

## 6. CI Vulnerability Scanning & Trivy Allowlist

Every changed microservice image built by `../spring-petclinic-microservices/.github/workflows/build-push.yml` is scanned locally (`linux/arm64`) **before** AWS OIDC login or `docker push` using the reusable composite action `.github/workflows/reusable/trivy-scan/action.yml` (`PETPLAT-105`, `PETPLAT-53`):

| Severity | Pipeline Behavior | Artifact / Audit Trail |
|----------|-------------------|------------------------|
| **CRITICAL** | **Fails build (`exit 1`)** — blocks ECR push and `repository_dispatch` | Included in `trivy-scan-<service>-<sha>` JSON artifact (30-day retention) |
| **HIGH** | Emits GitHub Actions `::warning::` annotations — **does not block** | Included in `trivy-scan-<service>-<sha>` JSON artifact + job summary |

### Reusable Pipeline Templates Inventory (`PETPLAT-53`)

| Repository | Composite Action Path | Responsibility |
|------------|----------------------|----------------|
| `spring-petclinic-microservices` | `.github/workflows/reusable/trivy-scan/action.yml` | Pre-push Trivy JSON audit, `HIGH` warnings, artifact upload, `CRITICAL` gate |
| `spring-petclinic-microservices` | `.github/workflows/reusable/ecr-login/action.yml` | OIDC `sts:AssumeRoleWithWebIdentity` + Amazon ECR Docker login |
| `spring-petclinic-microservices` | `.github/workflows/reusable/dispatch-platform/action.yml` | Sends `repository_dispatch` (`app-image-built`) with `{ sha, services }` |
| `petclinic-platform` | `.github/workflows/reusable/update-tags/action.yml` | Updates `.image.tag` via `yq`, runs `helm lint`, commits & pushes to `main` |

### Procedure: Review Trivy Scan Results and Add Accepted CVEs to Allowlist

**When:** `build-push.yml` fails on a `CRITICAL` CVE that has no upstream fix and is verified non-exploitable in Petclinic's runtime context.  
**Who:** Platform engineer with Security / Platform Lead approval.  
**Time:** ~10 minutes.

**Steps:**
1. List recent `Build, Scan, and Push ARM64 Images` workflow runs and download the Trivy JSON artifact for the failed build:
   ```bash
   gh run list --repo lyydev/spring-petclinic-microservices --workflow build-push.yml --limit 3
   gh run download <run-id> --repo lyydev/spring-petclinic-microservices --pattern "trivy-scan-*" --dir ./trivy-audit
   ```
2. Inspect `CRITICAL` findings (`VulnerabilityID`, package, installed version, and fixed version):
   ```bash
   jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL") | "\(.VulnerabilityID)\t\(.PkgName)\t\(.InstalledVersion)\tfix=\(.FixedVersion // "none")"' ./trivy-audit/*/trivy-results-*.json
   ```
3. **Prefer upgrading the dependency or base image first.** Only if no upstream fix exists and the code path is confirmed unreachable, add a time-bounded entry (`exp:YYYY-MM-DD`, max 30 days) to `../spring-petclinic-microservices/.trivyignore`:
   ```text
   CVE-2026-12345 exp:2026-11-30 # Transitive lib with no upstream patch; unreachable in runtime; approved by Platform Lead
   ```
4. Commit `.trivyignore` via pull request to `main` so `build-push.yml` re-evaluates the scan gate.

**Verify:**
- Confirm the subsequent workflow run passes the `Enforce Trivy CRITICAL vulnerability gate` step:
  ```bash
  gh run list --repo lyydev/spring-petclinic-microservices --workflow build-push.yml --limit 1
  ```
- Expected output:
  ```text
  STATUS     TITLE                              WORKFLOW                             BRANCH  EVENT  ID
  completed  chore(security): allowlist CVE...  Build, Scan, and Push ARM64 Images   main    push   12345678902
  ```

**Rollback:**
- Remove the CVE line from `.trivyignore` immediately once an upstream library or base-image patch is available (or allow `exp:YYYY-MM-DD` to expire automatically).
