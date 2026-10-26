# Secrets Management Guide

This document describes how secrets are managed, secured, and synchronized from AWS Secrets Manager into Amazon EKS using the External Secrets Operator (ESO).

---

## Architecture Overview

```
       +---------------------------------------------+
       |             AWS Secrets Manager             |
       |  petclinic/{env}/rds-credentials            |
       |  petclinic/{env}/openai-api-key             |
       +---------------------------------------------+
                              |
                              | IAM / IRSA
                              v
       +---------------------------------------------+
       |       External Secrets Operator (ESO)       |
       |       Namespace: `external-secrets`         |
       |       ServiceAccount: `external-secrets-sa` |
       +---------------------------------------------+
                              |
                              | Sync via ClusterSecretStore
                              v
       +---------------------------------------------+
       |              Kubernetes Secrets             |
       |  petclinic-dev / petclinic-prod namespaces  |
       |    - `rds-credentials` (username, password) |
       |    - `openai-api-key` (OPENAI_API_KEY)      |
       +---------------------------------------------+
```

---

## 1. AWS Secrets Manager Inventory

All secrets follow the naming convention `petclinic/{env}/{secret-name}` and are encrypted at rest.

| Secret Name | Content Type | Keys / Format | Managed By | Used By |
|---|---|---|---|---|
| `petclinic/{env}/rds-credentials` | JSON | `{"username":"...","password":"..."}` | Terraform `rds` module (`PETPLAT-23`) | `customers-service`, `visits-service`, `vets-service` |
| `petclinic/{env}/openai-api-key` | Plaintext | String (API Key) | Terraform `secrets` module (`PETPLAT-33`) | `genai-service` |

---

## 2. External Secrets Operator (ESO)

### Installation
ESO is deployed in the `external-secrets` namespace using [scripts/install-external-secrets.sh](file:///C:/Project/AIdevops/petclinic-platform/scripts/install-external-secrets.sh):

```bash
./scripts/install-external-secrets.sh dev
```

### IRSA Role
The ESO ServiceAccount `external-secrets-sa` assumes the IAM role `petclinic-{env}-eso-role` via AWS IAM Roles for Service Accounts (IRSA).
Permissions granted:
- `secretsmanager:GetSecretValue`
- `secretsmanager:DescribeSecret`
- Scope: `arn:aws:secretsmanager:*:*:secret:petclinic/*` and `arn:aws:secretsmanager:*:*:secret:${project}/${environment}/*`
- KMS: `kms:Decrypt` on cluster KMS keys.

### ClusterSecretStore
The cluster-wide store [k8s/base/external-secrets/cluster-secret-store.yaml](file:///C:/Project/AIdevops/petclinic-platform/k8s/base/external-secrets/cluster-secret-store.yaml) enables any namespace to sync secrets:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

---

## 3. How to Add a New Secret

Follow these step-by-step instructions to add a new secret to the Petclinic Platform:

### Step 1: Create the Secret in AWS Secrets Manager via Terraform
Add the secret resource to [terraform/modules/secrets/main.tf](file:///C:/Project/AIdevops/petclinic-platform/terraform/modules/secrets/main.tf):

```hcl
variable "my_new_secret" {
  description = "New secret description"
  type        = string
  sensitive   = true
  default     = "placeholder"
}

resource "aws_secretsmanager_secret" "my_new_secret" {
  name                    = "${var.project}/${var.environment}/my-new-secret"
  description             = "My new secret for ${var.project}-${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name        = "${var.project}-${var.environment}-my-new-secret"
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.project
  })
}

resource "aws_secretsmanager_secret_version" "my_new_secret" {
  secret_id     = aws_secretsmanager_secret.my_new_secret.id
  secret_string = var.my_new_secret
}
```

### Step 2: Create the `ExternalSecret` Resource in Kubernetes
Create a manifest in `k8s/base/external-secrets/my-new-secret.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-new-secret
  labels:
    app.kubernetes.io/name: my-new-secret
    app.kubernetes.io/part-of: petclinic
    app.kubernetes.io/managed-by: Helm
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-new-secret
    creationPolicy: Owner
  data:
    - secretKey: SECRET_KEY_NAME
      remoteRef:
        key: petclinic/dev/my-new-secret
```

### Step 3: Register in Kustomize Overlays
1. Add `my-new-secret.yaml` to `k8s/base/external-secrets/kustomization.yaml`.
2. In `k8s/overlays/prod/kustomization.yaml`, add a patch to replace `petclinic/dev/my-new-secret` with `petclinic/prod/my-new-secret`.

### Step 4: Mount or Inject into Application Pods
In `helm-values/{service}.yaml`:

```yaml
env:
  - name: SECRET_KEY_NAME
    valueFrom:
      secretKeyRef:
        name: my-new-secret
        key: SECRET_KEY_NAME
```

---

## 4. Secret Rotation and Refresh Procedures

- **Refresh Interval**: All ExternalSecrets specify `refreshInterval: 1h`. ESO polls AWS Secrets Manager every hour. When a secret value changes in AWS Secrets Manager, ESO updates the corresponding Kubernetes Secret automatically within 1 hour.
- **Immediate Refresh**: Trigger an immediate sync by annotating the `ExternalSecret`:
  ```bash
  kubectl annotate externalsecret rds-credentials -n petclinic-dev force-sync=$(date +%s) --overwrite
  ```
- **Pod Restarts**: Kubernetes does not automatically restart pods when a Secret changes. After updating a secret, perform a rollout restart of dependent deployments:
  ```bash
  kubectl rollout restart deployment/genai-service -n petclinic-dev
  ```
