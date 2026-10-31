#!/usr/bin/env bash
set -euo pipefail

#
# rollback.sh — Execute or preview deployment rollbacks across Petclinic environments.
#
# Story: PETPLAT-54
#
# Supported strategies:
#   1. gitops  (default, recommended) — Revert commit or pin previous SHA in helm-values/,
#                                       letting ArgoCD reconcile cluster state from Git.
#   2. argocd                         — Roll back an ArgoCD Application to a prior sync ID
#                                       (primarily for prod where auto-sync is manual).
#   3. kubectl                        — Emergency fallback via `kubectl rollout undo` in
#                                       reverse startup dependency order.
#
# Usage:
#   ./scripts/rollback.sh --strategy gitops --commit <bad-commit-sha> [--push]
#   ./scripts/rollback.sh --strategy gitops --service customers-service --tag 635f8be [--push]
#   ./scripts/rollback.sh --strategy argocd --env prod --service api-gateway --revision <id>
#   ./scripts/rollback.sh --strategy kubectl --env dev --service all
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

STRATEGY="gitops"
ENV="dev"
SERVICE="all"
COMMIT_SHA=""
TARGET_TAG=""
ARGOCD_REVISION=""
PUSH_CHANGES=false
AUTO_CONFIRM=false
DRY_RUN=false

# Reverse startup order: domain/edge services first, discovery second-to-last, config-server last
REVERSE_SERVICES=(
  "admin-server"
  "genai-service"
  "vets-service"
  "visits-service"
  "customers-service"
  "api-gateway"
  "discovery-server"
  "config-server"
)

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --strategy <gitops|argocd|kubectl>  Rollback mechanism (default: gitops)
  -e, --env <dev|prod>                Target environment (default: dev)
  -s, --service <name|all>            Target service name or 'all' (default: all)
  --commit <git-sha>                  [gitops] Git commit SHA of bad tag update to revert
  --tag <image-sha>                   [gitops] Known-good 7-char image SHA to restore in helm-values
  --revision <id>                     [argocd] ArgoCD history ID to roll back to
  --push                              [gitops] Push rollback commit to origin/main
  --yes                               Confirm production rollback non-interactively
  --dry-run                           Print actions without mutating Git, ArgoCD, or Kubernetes
  -h, --help                          Show this help message
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strategy)
      [[ $# -ge 2 ]] || { echo "Error: --strategy requires an argument (gitops|argocd|kubectl)." >&2; exit 1; }
      STRATEGY="$2"
      shift 2
      ;;
    -e|--env)
      [[ $# -ge 2 ]] || { echo "Error: $1 requires an environment argument (dev|prod)." >&2; exit 1; }
      ENV="$2"
      shift 2
      ;;
    -s|--service)
      [[ $# -ge 2 ]] || { echo "Error: $1 requires a service name or 'all'." >&2; exit 1; }
      SERVICE="$2"
      shift 2
      ;;
    --commit)
      [[ $# -ge 2 ]] || { echo "Error: --commit requires a git commit SHA or HEAD." >&2; exit 1; }
      COMMIT_SHA="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || { echo "Error: --tag requires a 7-40 hex image SHA." >&2; exit 1; }
      TARGET_TAG="$2"
      shift 2
      ;;
    --revision)
      [[ $# -ge 2 ]] || { echo "Error: --revision requires a numeric ArgoCD history ID." >&2; exit 1; }
      ARGOCD_REVISION="$2"
      shift 2
      ;;
    --push)
      PUSH_CHANGES=true
      shift
      ;;
    --yes)
      AUTO_CONFIRM=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "Error: --env must be 'dev' or 'prod' (received '${ENV}')" >&2
  exit 1
fi

if [[ -n "${COMMIT_SHA}" && "${COMMIT_SHA}" != "HEAD" && ! "${COMMIT_SHA}" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
  echo "Error: --commit must be 'HEAD' or a valid 7-40 hex git commit SHA (received '${COMMIT_SHA}')." >&2
  exit 1
fi

if [[ -n "${ARGOCD_REVISION}" && ! "${ARGOCD_REVISION}" =~ ^[0-9]+$ ]]; then
  echo "Error: --revision must be a numeric ArgoCD history ID (received '${ARGOCD_REVISION}')." >&2
  exit 1
fi

if [[ "${SERVICE}" == "all" ]]; then
  TARGETS=("${REVERSE_SERVICES[@]}")
else
  VALID=false
  for svc in "${REVERSE_SERVICES[@]}"; do
    if [[ "${svc}" == "${SERVICE}" ]]; then
      VALID=true
      break
    fi
  done
  if [[ "${VALID}" != "true" ]]; then
    echo "Error: Unknown service '${SERVICE}'." >&2
    exit 1
  fi
  TARGETS=("${SERVICE}")
fi

confirm_prod() {
  local needs_confirm=false
  local prompt_msg="Rolling back ${SERVICE} in PRODUCTION (petclinic-prod) via ${STRATEGY}. Confirm? [y/N] "
  if [[ "${ENV}" == "prod" ]]; then
    needs_confirm=true
  elif [[ "${STRATEGY}" == "gitops" && "${PUSH_CHANGES}" == "true" ]]; then
    needs_confirm=true
    prompt_msg="Pushing GitOps rollback for ${SERVICE} to origin/main (shared base helm-values for dev & prod). Confirm? [y/N] "
  fi

  if [[ "${needs_confirm}" == "true" && "${AUTO_CONFIRM}" != "true" && "${DRY_RUN}" != "true" ]]; then
    read -r -p "${prompt_msg}" REPLY
    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 1
    fi
  fi
}

case "${STRATEGY}" in
  gitops)
    echo "Note: helm-values/{service}.yaml defines the shared base image.tag across dev (auto-sync) and prod (manual sync)."
    confirm_prod
    cd "${ROOT_DIR}"
    if [[ -n "${COMMIT_SHA}" ]]; then
      echo "[GitOps Rollback] Reverting commit ${COMMIT_SHA}..."
      if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [DRY-RUN] git revert --no-edit -- ${COMMIT_SHA}"
      else
        git revert --no-edit -- "${COMMIT_SHA}"
        bash "${SCRIPT_DIR}/validate-helm.sh"
        if [[ "${PUSH_CHANGES}" == "true" ]]; then
          git push origin HEAD:main
        else
          echo "Rollback commit created locally. Run 'git push origin main' (or pass --push) to trigger ArgoCD."
        fi
      fi
    elif [[ -n "${TARGET_TAG}" ]]; then
      if [[ "${TARGET_TAG,,}" == "latest" || ! "${TARGET_TAG}" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
        echo "Error: --tag must be a valid 7-40 hex commit SHA (never 'latest')." >&2
        exit 1
      fi
      SHORT_TAG="${TARGET_TAG:0:7}"
      SHORT_TAG="${SHORT_TAG,,}"

      echo "[GitOps Rollback] Restoring image.tag=${SHORT_TAG} for: ${TARGETS[*]}"
      if [[ "${DRY_RUN}" == "true" ]]; then
        for svc in "${TARGETS[@]}"; do
          echo "  [DRY-RUN] yq -i '.image.tag = \"${SHORT_TAG}\"' helm-values/${svc}.yaml"
        done
      else
        if ! command -v yq >/dev/null 2>&1; then
          echo "Error: 'yq' is required for --tag GitOps rollback (or use --commit <git-sha>)." >&2
          exit 1
        fi
        for svc in "${TARGETS[@]}"; do
          IMAGE_TAG="${SHORT_TAG}" yq -i '.image.tag = strenv(IMAGE_TAG) | .image.tag style="double"' "helm-values/${svc}.yaml"
        done
        bash "${SCRIPT_DIR}/validate-helm.sh"
        git add helm-values/*.yaml
        git commit -m "revert: roll back image tags to ${SHORT_TAG} (${TARGETS[*]})"
        if [[ "${PUSH_CHANGES}" == "true" ]]; then
          git push origin HEAD:main
        else
          echo "Rollback commit created locally. Run 'git push origin main' (or pass --push) to trigger ArgoCD."
        fi
      fi
    else
      echo "Error: --strategy gitops requires either --commit <git-sha> or --tag <image-sha>." >&2
      exit 1
    fi
    ;;

  argocd)
    confirm_prod
    if [[ "${ENV}" == "dev" ]]; then
      echo "Warning: petclinic-dev uses ArgoCD automated sync + selfHeal. Prefer '--strategy gitops' so ArgoCD does not overwrite the rollback." >&2
    fi
    for svc in "${TARGETS[@]}"; do
      APP_NAME="${svc}-${ENV}"
      if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [DRY-RUN] argocd app history ${APP_NAME}"
        echo "  [DRY-RUN] argocd app rollback ${APP_NAME} ${ARGOCD_REVISION:-<previous-id>}"
      else
        argocd app history "${APP_NAME}"
        if [[ -n "${ARGOCD_REVISION}" ]]; then
          argocd app rollback "${APP_NAME}" "${ARGOCD_REVISION}"
        else
          argocd app rollback "${APP_NAME}"
        fi
        argocd app wait "${APP_NAME}" --health --timeout 180
      fi
    done
    ;;

  kubectl)
    confirm_prod
    NAMESPACE="petclinic-${ENV}"
    echo "Warning: 'kubectl rollout undo' is an emergency out-of-band fallback. Follow up with a Git revert so ArgoCD state matches." >&2
    for svc in "${TARGETS[@]}"; do
      if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [DRY-RUN] kubectl rollout undo deployment/${svc} -n ${NAMESPACE}"
        echo "  [DRY-RUN] kubectl rollout status deployment/${svc} -n ${NAMESPACE} --timeout=120s"
      else
        kubectl rollout undo "deployment/${svc}" -n "${NAMESPACE}"
        kubectl rollout status "deployment/${svc}" -n "${NAMESPACE}" --timeout=120s
      fi
    done
    ;;

  *)
    echo "Error: Unsupported strategy '${STRATEGY}'. Choose gitops, argocd, or kubectl." >&2
    exit 1
    ;;
esac
