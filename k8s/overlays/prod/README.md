# Prod Overlay Settings (`petclinic-prod`)

This overlay defines the production environment overrides on top of `k8s/base/`. These settings serve as the specification for `helm-values/prod.yaml` in Epic E-16.

## Environment Settings Summary

| Service | Replicas | HPA (Min/Max/CPU) | PDB (`minAvailable`) | Notes |
|---------|----------|-------------------|----------------------|-------|
| `config-server` | 2 | Disabled | `1` | HA for config distribution |
| `discovery-server` | 2 | Disabled | `1` | HA for Eureka service registry |
| `api-gateway` | 2 | `2` / `6` / `70%` | `1` | Public-facing entry point (`200m`/`1000m` CPU) |
| `customers-service` | 2 | `2` / `4` / `70%` | `1` | HA domain service |
| `visits-service` | 2 | `2` / `4` / `70%` | `1` | HA domain service |
| `vets-service` | 2 | `2` / `4` / `70%` | `1` | HA domain service |
| `genai-service` | 1 | `1` / `3` / `70%` | Disabled | Lower priority, cost saving |
| `admin-server` | 1 | Disabled | Disabled | Monitoring dashboard, single replica sufficient |

## Additional Production Settings

- **Namespace:** `petclinic-prod`
- **Image Registry:** `037547369073.dkr.ecr.us-east-1.amazonaws.com/petclinic-prod/{service}`
- **Image Tag:** Release or commit SHA tag (`v1.0.0`)
- **Image Pull Policy:** `Always`
- **ResourceQuota:** `4` CPU, `4Gi` Memory, `30` Pods (`resource-quota.yaml`)
- **Ingress Host:** `petclinic.k8s.lyaistorm.win`
- **Secrets Manager Prefix:** `petclinic/prod/*`

## Translation to `helm-values/prod.yaml` (E-16)

```yaml
environment: prod
namespace: petclinic-prod
replicaCount: 2

image:
  registry: 037547369073.dkr.ecr.us-east-1.amazonaws.com/petclinic-prod
  pullPolicy: Always

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 4
  targetCPUUtilizationPercentage: 70

podDisruptionBudget:
  enabled: true
  minAvailable: 1
```
