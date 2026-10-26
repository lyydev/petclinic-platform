# Dev Overlay Settings (`petclinic-dev`)

This overlay defines the development environment overrides on top of `k8s/base/`. These settings serve as the specification for `helm-values/dev.yaml` in Epic E-16.

## Environment Settings Summary

| Parameter | Dev Value | Notes |
|-----------|-----------|-------|
| Namespace | `petclinic-dev` | Enforces `baseline` PSA, warns/audits `restricted` |
| Replicas (all 8 services) | `1` | Single replica per service to fit on 2x `t4g.small` nodes |
| Image Registry | `037547369073.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/{service}` | ECR private repositories in `us-east-1` |
| Image Tag | `v1.0.0` (initial) / Commit SHA | Updated by CI pipeline |
| Image Pull Policy | `Always` | Ensures latest image for tag is pulled |
| CPU / Memory (standard) | `100m` req / `500m` limit, `128Mi` req / `512Mi` limit | Standard for 7 services |
| CPU / Memory (`api-gateway`) | `200m` req / `1000m` limit, `128Mi` req / `512Mi` limit | Higher CPU for gateway routing |
| HPA | Disabled | Prod only |
| PDB | Disabled | Prod only |
| ResourceQuota | `4` CPU, `4Gi` Memory, `30` Pods | Enforced via `resource-quota.yaml` |
| Ingress Host | `petclinic-dev.k8s.lyaistorm.win` | Internet-facing ALB |
| Secrets Manager Prefix | `petclinic/dev/*` | Synced via External Secrets Operator |

## Translation to `helm-values/dev.yaml` (E-16)

```yaml
environment: dev
namespace: petclinic-dev
replicaCount: 1

image:
  registry: 037547369073.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev
  pullPolicy: Always

autoscaling:
  enabled: false

podDisruptionBudget:
  enabled: false
```
