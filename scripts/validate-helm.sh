#!/usr/bin/env bash
set -euo pipefail

#
# validate-helm.sh — Lint, render, and client-side dry-run validate the Petclinic
#                    generic Helm chart across all services and environments.
#
# Story: PETPLAT-110
#
# Usage:
#   ./scripts/validate-helm.sh
#   ./scripts/validate-helm.sh --env dev
#   ./scripts/validate-helm.sh --service customers-service
#   ./scripts/validate-helm.sh --env prod --service api-gateway
#   ./scripts/validate-helm.sh --output-dir /tmp/rendered-manifests
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHART_DIR="${ROOT_DIR}/helm/petclinic-service"
VALUES_DIR="${ROOT_DIR}/helm-values"

ALL_ENVIRONMENTS=("dev" "prod")
ALL_SERVICES=(
  "config-server"
  "discovery-server"
  "api-gateway"
  "customers-service"
  "visits-service"
  "vets-service"
  "genai-service"
  "admin-server"
)

FILTER_ENV=""
FILTER_SERVICE=""
OUTPUT_DIR=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -e, --env <dev|prod>       Validate only the specified environment
  -s, --service <name>       Validate only the specified service
  -o, --output-dir <path>    Write rendered YAML manifests to <path>/<env>/<service>.yaml
  -h, --help                 Show this help message

Examples:
  $0                                         # Validate all 16 releases (8 services x 2 envs)
  $0 --env prod                              # Validate all 8 services with prod values
  $0 --service visits-service                # Validate visits-service for dev and prod
  $0 --env dev --service customers-service   # Validate a single service + environment
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--env)
      FILTER_ENV="$2"
      shift 2
      ;;
    -s|--service)
      FILTER_SERVICE="$2"
      shift 2
      ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"
      shift 2
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

for cmd in helm kubectl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: Required command '${cmd}' not found in PATH." >&2
    exit 1
  fi
done

if [[ ! -d "${CHART_DIR}" ]]; then
  echo "Error: Helm chart directory not found at ${CHART_DIR}" >&2
  exit 1
fi

ENVIRONMENTS=("${ALL_ENVIRONMENTS[@]}")
if [[ -n "${FILTER_ENV}" ]]; then
  if [[ "${FILTER_ENV}" != "dev" && "${FILTER_ENV}" != "prod" ]]; then
    echo "Error: --env must be 'dev' or 'prod' (received '${FILTER_ENV}')" >&2
    exit 1
  fi
  ENVIRONMENTS=("${FILTER_ENV}")
fi

SERVICES=("${ALL_SERVICES[@]}")
if [[ -n "${FILTER_SERVICE}" ]]; then
  VALID_SVC=false
  for svc in "${ALL_SERVICES[@]}"; do
    if [[ "${svc}" == "${FILTER_SERVICE}" ]]; then
      VALID_SVC=true
      break
    fi
  done
  if [[ "${VALID_SVC}" != "true" ]]; then
    echo "Error: Unknown service '${FILTER_SERVICE}'. Valid services: ${ALL_SERVICES[*]}" >&2
    exit 1
  fi
  SERVICES=("${FILTER_SERVICE}")
fi

echo "=========================================================="
echo "  Petclinic Helm Chart Validation"
echo "  Chart        : helm/petclinic-service"
echo "  Environments : ${ENVIRONMENTS[*]}"
echo "  Services     : ${#SERVICES[@]} (${SERVICES[*]})"
echo "=========================================================="
echo ""

echo "[Step 1/2] Base chart lint: helm lint helm/petclinic-service/"
helm lint "${CHART_DIR}"
echo ""

echo "[Step 2/2] Validating service + environment combinations..."
PASSED=0
FAILED=0
TEMP_RENDER="$(mktemp)"
trap 'rm -f "${TEMP_RENDER}"' EXIT

for env in "${ENVIRONMENTS[@]}"; do
  ENV_VALUES="${VALUES_DIR}/${env}.yaml"
  NAMESPACE="petclinic-${env}"

  if [[ ! -f "${ENV_VALUES}" ]]; then
    echo "  [FAIL] Missing environment values file: ${ENV_VALUES}" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  if [[ -n "${OUTPUT_DIR}" ]]; then
    mkdir -p "${OUTPUT_DIR}/${env}"
  fi

  for svc in "${SERVICES[@]}"; do
    SVC_VALUES="${VALUES_DIR}/${svc}.yaml"
    LABEL="${svc} (${env})"

    if [[ ! -f "${SVC_VALUES}" ]]; then
      echo "  [FAIL] ${LABEL} — missing service values file: ${SVC_VALUES}" >&2
      FAILED=$((FAILED + 1))
      continue
    fi

    echo "----------------------------------------------------------"
    echo "Validating: ${LABEL}"

    # 1. Helm lint with merged values
    if ! helm lint "${CHART_DIR}" -f "${SVC_VALUES}" -f "${ENV_VALUES}" >/dev/null; then
      echo "  [FAIL] ${LABEL} — helm lint failed" >&2
      helm lint "${CHART_DIR}" -f "${SVC_VALUES}" -f "${ENV_VALUES}" || true
      FAILED=$((FAILED + 1))
      continue
    fi
    echo "  [OK] helm lint"

    # 2. Helm template render
    if ! helm template "${svc}" "${CHART_DIR}" \
      -n "${NAMESPACE}" \
      -f "${SVC_VALUES}" \
      -f "${ENV_VALUES}" > "${TEMP_RENDER}"; then
      echo "  [FAIL] ${LABEL} — helm template failed" >&2
      FAILED=$((FAILED + 1))
      continue
    fi
    echo "  [OK] helm template"

    if [[ -n "${OUTPUT_DIR}" ]]; then
      cp "${TEMP_RENDER}" "${OUTPUT_DIR}/${env}/${svc}.yaml"
    fi

    # 3. Kubernetes client-side dry-run validation
    if ! kubectl apply --dry-run=client -f "${TEMP_RENDER}" >/dev/null; then
      echo "  [FAIL] ${LABEL} — kubectl apply --dry-run=client failed" >&2
      kubectl apply --dry-run=client -f "${TEMP_RENDER}" || true
      FAILED=$((FAILED + 1))
      continue
    fi
    echo "  [OK] kubectl apply --dry-run=client"

    PASSED=$((PASSED + 1))
  done
done

echo ""
echo "=========================================================="
echo "  Validation Summary"
echo "  Passed : ${PASSED}"
echo "  Failed : ${FAILED}"
echo "=========================================================="

if [[ "${FAILED}" -gt 0 ]]; then
  exit 1
fi
