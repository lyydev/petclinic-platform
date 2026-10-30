# Helm Chart Guide — Petclinic Platform

**Last Updated:** 2026-10-29  
**Purpose:** Document the structure, values hierarchy, operational procedures, and GitOps integration for the generic `petclinic-service` Helm chart (Epic E-16: PETPLAT-107 through PETPLAT-111).

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Chart Structure](#2-chart-structure)
3. [Values Hierarchy and Merge Order](#3-values-hierarchy-and-merge-order)
4. [Service Configuration Matrix](#4-service-configuration-matrix)
5. [Operational Procedures](#5-operational-procedures)
   - [Deploy a Service Manually with Helm](#procedure-deploy-a-service-manually-with-helm)
   - [Add a New Microservice](#procedure-add-a-new-microservice)
   - [Modify Resources, Replicas, or Environment Variables](#procedure-modify-resources-replicas-or-environment-variables)
   - [Validate Chart Changes Locally](#procedure-validate-chart-changes-locally)
6. [GitOps Integration with ArgoCD](#6-gitops-integration-with-argocd)

---

## 1. Architecture Overview

All 8 Spring Petclinic microservices share a **single generic Helm chart** at `helm/petclinic-service/`. This replaces duplicated raw Kubernetes YAML and Kustomize patches (`k8s/base/{service}/` and `k8s/overlays/{env}/`) with a single set of templates parameterized by per-service and per-environment values files in `helm-values/` (see [ADR-0007](./technical-spec.md#adr-index)).

Cluster-level and non-service resources — namespaces (`k8s/base/namespaces.yaml`), External Secrets Operator CRs (`k8s/base/external-secrets/`), ResourceQuotas, and ALB Ingress (`k8s/base/ingress/`) — remain outside the service chart.

---

## 2. Chart Structure

```text
helm/petclinic-service/
├── Chart.yaml                  # Chart metadata (v0.1.0, appVersion 4.0.1)
├── values.yaml                 # Baseline defaults shared across all services
└── templates/
    ├── _helpers.tpl            # Name, namespace, image URI, and label helpers
    ├── deployment.yaml         # Deployment (probes, resources, securityContext, initContainers, env/secrets)
    ├── service.yaml            # ClusterIP Service matching containerPort
    ├── configmap.yaml          # Conditional ConfigMap (<service>-config) when configMap.data is non-empty
    ├── serviceaccount.yaml     # ServiceAccount with automountServiceAccountToken: false and optional IRSA annotations
    ├── hpa.yaml                # Conditional HorizontalPodAutoscaler (autoscaling/v2) when autoscaling.enabled=true
    ├── pdb.yaml                # Conditional PodDisruptionBudget (policy/v1) when podDisruptionBudget.enabled=true
    └── NOTES.txt               # Post-install rollout and port-forward commands

helm-values/
├── config-server.yaml          # Port 8888, Git config URI, no initContainers
├── discovery-server.yaml       # Port 8761, waits for config-server
├── api-gateway.yaml            # Port 8080, 200m/1000m CPU, waits for config + discovery
├── customers-service.yaml      # Port 8081, docker,mysql profile, RDS secret refs
├── visits-service.yaml         # Port 8082, docker,mysql profile, waits for config + discovery + customers
├── vets-service.yaml           # Port 8083, docker,mysql profile, RDS secret refs
├── genai-service.yaml          # Port 8084, openai-api-key secret ref
├── admin-server.yaml           # Port 9090, Spring Boot Admin
├── dev.yaml                    # Dev overrides (petclinic-dev, 1 replica, no HPA/PDB, dev ECR & RDS)
└── prod.yaml                   # Prod overrides (petclinic-prod, per-service replicas/HPA/PDB, prod ECR & RDS)
```

### Standard Labels and Resource Naming

- Every per-service values file sets `nameOverride` and `fullnameOverride` to `{service}` so Kubernetes `Service` DNS names (e.g., `http://config-server:8888`, `http://discovery-server:8761`) remain stable regardless of the Helm release name or ArgoCD Application name (`{service}-{env}`).
- Every rendered resource includes `app.kubernetes.io/name`, `app.kubernetes.io/part-of: petclinic`, `app.kubernetes.io/managed-by: Helm`, `app.kubernetes.io/component`, `app.kubernetes.io/version`, and `helm.sh/chart`.
- Immutable selector labels (`Deployment.spec.selector.matchLabels`, `Service.spec.selector`, `PodDisruptionBudget.spec.selector.matchLabels`) use only `app.kubernetes.io/name` and `app.kubernetes.io/part-of: petclinic`.

---

## 3. Values Hierarchy and Merge Order

Helm merges values in strict left-to-right precedence (**later files win**):

```text
1. helm/petclinic-service/values.yaml     (Chart defaults — lowest precedence)
        │
        ▼
2. helm-values/{service}.yaml             (Per-service ports, probes, env, secrets, initContainers)
        │
        ▼
3. helm-values/{env}.yaml                 (Per-environment namespace, ECR registry, RDS URL, scaling — highest precedence)
```

### Key Templating Mechanisms

1. **Image URI construction (`petclinic-service.image`):**
   - Renders `{{ .Values.image.registry }}/{{ .Values.image.name }}:{{ .Values.image.tag }}` when `image.registry` is set in `helm-values/{env}.yaml`.
   - CI updates `image.tag` (7-char commit SHA, never `latest`) in `helm-values/{service}.yaml`, while `dev.yaml` and `prod.yaml` point to `petclinic-dev` and `petclinic-prod` ECR repositories respectively.
2. **Environment-aware ConfigMap interpolation:**
   - `configMap.data` values are rendered through Helm's `tpl` function. Database services set `SPRING_DATASOURCE_URL: "{{ .Values.datasource.url }}"` in their service file, which resolves to the `dev` or `prod` RDS endpoint defined in `helm-values/{env}.yaml`.
3. **Per-service production scaling (`services.<service-name>`):**
   - Because production replica counts, HPA bounds, and PDB eligibility differ per microservice, `helm-values/prod.yaml` defines exact per-service overrides under `services.<service-name>`. Templates merge `services.<service-name>` over top-level `replicaCount`, `autoscaling`, `podDisruptionBudget`, and `resources`.

---

## 4. Service Configuration Matrix

| Service | Port | Spring Profiles | Init Containers | Secrets (`ExternalSecret` target) | Dev Replicas | Prod Replicas | Prod HPA (Min/Max/CPU) | Prod PDB (`minAvailable`) |
|---------|------|-----------------|-----------------|-----------------------------------|--------------|---------------|------------------------|---------------------------|
| `config-server` | 8888 | `docker` | None | None | 1 | 2 | Disabled | `1` |
| `discovery-server` | 8761 | `docker` | `config-server` | None | 1 | 2 | Disabled | `1` |
| `api-gateway` | 8080 | `docker` | `config-server`, `discovery-server` | None | 1 | 2 | `2` / `6` / `70%` | `1` |
| `customers-service` | 8081 | `docker,mysql` | `config-server`, `discovery-server` | `rds-credentials` (`username`, `password`) | 1 | 2 | `2` / `4` / `70%` | `1` |
| `visits-service` | 8082 | `docker,mysql` | `config-server`, `discovery-server`, `customers-service` | `rds-credentials` (`username`, `password`) | 1 | 2 | `2` / `4` / `70%` | `1` |
| `vets-service` | 8083 | `docker,mysql` | `config-server`, `discovery-server` | `rds-credentials` (`username`, `password`) | 1 | 2 | `2` / `4` / `70%` | `1` |
| `genai-service` | 8084 | `docker` | `config-server`, `discovery-server` | `openai-api-key` (`OPENAI_API_KEY`) | 1 | 1 | `1` / `3` / `70%` | Disabled |
| `admin-server` | 9090 | `docker` | `config-server`, `discovery-server` | None | 1 | 1 | Disabled | Disabled |

---

## 5. Operational Procedures

### Procedure: Deploy a Service Manually with Helm

**When:** Initial cluster bootstrap before ArgoCD is installed, or emergency manual testing in `dev`.  
**Who:** On-call engineer or platform engineer with EKS cluster access.  
**Time:** ~2–5 minutes per service.

**Steps:**
1. Configure `kubectl` context for the target EKS cluster (`dev` or `prod`):
   ```bash
   aws eks update-kubeconfig --name petclinic-{env} --region us-east-1
   ```
2. Ensure target namespaces and ExternalSecrets exist so Kubernetes Secrets (`rds-credentials`, `openai-api-key`) are synced before pod startup:
   ```bash
   kubectl apply -f k8s/base/namespaces.yaml
   kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml
   sed 's|petclinic/ENV/|petclinic/dev/|g' k8s/base/external-secrets/rds-credentials.yaml | kubectl apply -n petclinic-dev -f -
   sed 's|petclinic/ENV/|petclinic/dev/|g' k8s/base/external-secrets/openai-api-key.yaml | kubectl apply -n petclinic-dev -f -
   ```
3. Install or upgrade the service release (deploy `config-server` first, `discovery-server` second, then domain services):
   ```bash
   helm upgrade --install customers-service helm/petclinic-service/ \
     -n petclinic-dev \
     -f helm-values/customers-service.yaml \
     -f helm-values/dev.yaml \
     --set image.tag=635f8be
   ```

**Verify:**
- Check rollout completion and pod health:
  ```bash
  kubectl rollout status deployment/customers-service -n petclinic-dev --timeout=180s
  kubectl get pods,svc,cm -n petclinic-dev -l app.kubernetes.io/name=customers-service
  ```

**Rollback:**
- Revert to the previous Helm release revision:
  ```bash
  helm rollback customers-service -n petclinic-dev
  kubectl rollout status deployment/customers-service -n petclinic-dev --timeout=120s
  ```

---

### Procedure: Add a New Microservice

**When:** Onboarding a 9th+ Spring Boot microservice onto the Petclinic platform.  
**Who:** Platform engineer.  
**Time:** ~15 minutes.

**Steps:**
1. Add the service name to `service_names` in the `module "ecr"` block of `terraform/environments/{dev,prod}/main.tf` so ECR repositories `petclinic-{env}/{new-service}` are provisioned.
2. Create `helm-values/{new-service}.yaml` modeled on an existing service file:
   ```yaml
   nameOverride: billing-service
   fullnameOverride: billing-service
   component: service

   image:
     name: billing-service
     repository: <aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/billing-service
     tag: "635f8be"
     pullPolicy: Always

   containerPort: 8085
   service:
     type: ClusterIP
     port: 8085

   springProfiles: "docker"

   configMap:
     enabled: true
     data:
       CONFIG_SERVER_URL: "http://config-server:8888"
       DISCOVERY_SERVER_URL: "http://discovery-server:8761/eureka"

   initContainers:
     - name: wait-for-config-server
       image: busybox:1.36
       command: ["sh", "-c", "until wget -qO- http://config-server:8888/actuator/health; do sleep 5; done"]
     - name: wait-for-discovery-server
       image: busybox:1.36
       command: ["sh", "-c", "until wget -qO- http://discovery-server:8761/actuator/health; do sleep 5; done"]
   ```
3. Add production scaling overrides under `services.billing-service` in `helm-values/prod.yaml` (replica count, `autoscaling`, and `podDisruptionBudget`).
4. Add `"billing-service"` to `ALL_SERVICES` in `scripts/validate-helm.sh`.
5. Create ArgoCD `Application` manifests in `k8s/argocd/applications/dev/billing-service.yaml` and `k8s/argocd/applications/prod/billing-service.yaml` (see Section 6).

**Verify:**
- Lint, render, and dry-run both environments:
  ```bash
  helm lint helm/petclinic-service/ -f helm-values/billing-service.yaml -f helm-values/dev.yaml
  helm template billing-service helm/petclinic-service/ -f helm-values/billing-service.yaml -f helm-values/prod.yaml | kubectl apply --dry-run=client -f -
  ```

**Rollback:**
- Revert the Git commit adding the values and ArgoCD Application manifests (`git revert <commit-sha>`).

---

### Procedure: Modify Resources, Replicas, or Environment Variables

**When:** Tuning JVM CPU/memory allocations, scaling replicas/HPA bounds, or adding non-secret/secret environment variables.  
**Who:** Platform engineer or application developer via Pull Request.  
**Time:** ~10 minutes.

**Steps:**
1. **Change CPU/Memory requests or limits:**
   - For a single service across all environments, update `resources` in `helm-values/{service}.yaml`:
     ```yaml
     resources:
       requests:
         cpu: 200m
         memory: 128Mi
       limits:
         cpu: 1000m
         memory: 512Mi
     ```
   - For a production-only override on a specific service, set `services.{service}.resources` in `helm-values/prod.yaml`.
2. **Change replica counts, HPA, or PDB:**
   - Dev replicas are controlled globally via `replicaCount: 1` in `helm-values/dev.yaml`.
   - Prod replicas, HPA (`minReplicas`, `maxReplicas`, `targetCPUUtilizationPercentage`), and PDB (`minAvailable`) are configured per-service under `services.{service}` in `helm-values/prod.yaml`.
3. **Add a non-secret environment variable:**
   - Add a ConfigMap-backed key under `configMap.data` in `helm-values/{service}.yaml` (automatically mounted into the container via `configMapKeyRef`), or add a direct entry to `env`:
     ```yaml
     env:
       - name: MANAGEMENT_TRACING_SAMPLING_PROBABILITY
         value: "1.0"
     ```
4. **Add a secret-backed environment variable (never store plaintext secrets in YAML):**
   - Provision the secret in AWS Secrets Manager (`terraform/modules/secrets/`) and create an `ExternalSecret` in `k8s/base/external-secrets/`.
   - Reference the synced Kubernetes `Secret` in `helm-values/{service}.yaml`:
     ```yaml
     secrets:
       - name: MY_SECRET_ENV
         secretName: my-k8s-secret
         key: secret_property
     ```

**Verify:**
- Run the validation suite to confirm all 16 releases render cleanly:
  ```bash
  ./scripts/validate-helm.sh
  ```

**Rollback:**
- Revert the values change in Git (`git revert <commit-sha>`). ArgoCD auto-syncs `dev`; trigger `argocd app sync {service}-prod` for `prod`.

---

### Procedure: Validate Chart Changes Locally

**When:** Before committing any edits to `helm/petclinic-service/` or `helm-values/`.  
**Who:** Any contributor.  
**Time:** < 30 seconds.

**Steps:**
1. Run the automated validation script across all 8 services and both environments:
   ```bash
   ./scripts/validate-helm.sh
   ```
2. Optionally filter by environment or service, or inspect rendered manifests on disk:
   ```bash
   ./scripts/validate-helm.sh --env prod --service visits-service
   ./scripts/validate-helm.sh --output-dir /tmp/petclinic-rendered
   ```

**Verify:**
- Confirm output reports `Passed : 16` and `Failed : 0`.

**Rollback:**
- Local read-only check; no cluster state is modified.

---

## 6. GitOps Integration with ArgoCD

In steady-state operations (Epic E-17, [ADR-0008](./technical-spec.md#adr-index)), GitHub Actions **never** runs `helm upgrade` or `kubectl apply`:

1. **CI (Cross-Repo Pipeline):**
   - Application repository fork (`spring-petclinic-microservices`) runs `.github/workflows/build-push.yml` to build `linux/arm64` images, scan with Trivy, push to ECR, and emit a `repository_dispatch` event.
   - Platform repository (`petclinic-platform`) runs `.github/workflows/update-image-tags.yml` to update `image.tag` in `helm-values/{service}.yaml`:
     ```bash
     yq -i ".image.tag = \"${SHA}\"" helm-values/${service}.yaml
     ```
2. **CD (`k8s/argocd/applications/{dev,prod}/{service}.yaml`):**
   - Each ArgoCD `Application` points to `path: helm/petclinic-service` and merges the two values files:
     ```yaml
     source:
       repoURL: https://github.com/<org>/petclinic-platform.git
       targetRevision: main
       path: helm/petclinic-service
       helm:
         valueFiles:
           - ../../helm-values/{service}.yaml
           - ../../helm-values/{env}.yaml
     ```
   - **Dev (`petclinic-dev`):** `automated` sync policy (`prune: true`, `selfHeal: true`) deploys image tag and configuration changes automatically.
   - **Prod (`petclinic-prod`):** Manual sync policy requires explicit operator approval via `argocd app sync {service}-prod` or the ArgoCD UI.
