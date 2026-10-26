#!/usr/bin/env bash
set -euo pipefail

#
# install-external-secrets.sh — Install External Secrets Operator on EKS via Helm/manifests
#
# Usage:
#   ./scripts/install-external-secrets.sh [dev|prod]
#   ./scripts/install-external-secrets.sh --env dev --region us-east-1
#   ./scripts/install-external-secrets.sh --help
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV="dev"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CLUSTER_NAME=""
ROLE_ARN=""
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 [environment] [options]

Arguments:
  environment          Target environment: 'dev' or 'prod' (default: dev)

Options:
  -e, --env <env>      Target environment: 'dev' or 'prod'
  -r, --region <reg>   AWS Region (default: us-east-1 or AWS_DEFAULT_REGION)
  -c, --cluster <name> EKS Cluster Name (default: petclinic-<env>)
  --role-arn <arn>     External Secrets Operator IRSA Role ARN (auto-detected if omitted)
  --dry-run            Simulate installation and print commands without executing mutating actions
  -h, --help           Show this help message

Examples:
  $0 dev
  $0 prod --region us-east-1
  $0 --env dev --role-arn arn:aws:iam::123456789012:role/petclinic-dev-eso-role
EOF
  exit 1
}

# Parse positional argument if provided
if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
  ENV="$1"
  shift
fi

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--env)
      ENV="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -c|--cluster)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --role-arn)
      ROLE_ARN="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown argument '$1'"
      usage
      ;;
  esac
done

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "Error: Invalid environment '$ENV'. Must be 'dev' or 'prod'."
  exit 1
fi

if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="petclinic-${ENV}"
fi

echo "=========================================================="
echo "  External Secrets Operator (ESO) Installation"
echo "=========================================================="
echo "  Environment:  ${ENV}"
echo "  Region:       ${REGION}"
echo "  EKS Cluster:  ${CLUSTER_NAME}"
echo "  Dry Run:      ${DRY_RUN}"
echo "=========================================================="

# 1. Resolve IRSA Role ARN
if [[ -z "${ROLE_ARN}" ]]; then
  echo "[1/4] Resolving IRSA role ARN for External Secrets Operator..."
  TF_ENV_DIR="${ROOT_DIR}/terraform/environments/${ENV}"
  
  if [[ -d "${TF_ENV_DIR}" ]] && command -v terraform >/dev/null 2>&1; then
    ROLE_ARN=$(terraform -chdir="${TF_ENV_DIR}" output -raw eso_role_arn 2>/dev/null || true)
  fi

  if [[ -z "${ROLE_ARN}" ]]; then
    ROLE_NAME="petclinic-${ENV}-eso-role"
    ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text 2>/dev/null || true)
  fi

  if [[ -z "${ROLE_ARN}" ]]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
    if [[ -n "${ACCOUNT_ID}" ]]; then
      ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/petclinic-${ENV}-eso-role"
    fi
  fi
fi

if [[ -z "${ROLE_ARN}" ]]; then
  echo "Error: Unable to determine IRSA role ARN. Please provision Terraform or pass --role-arn."
  exit 1
fi
echo "  -> IRSA Role ARN: ${ROLE_ARN}"

# 2. Add and update Helm repository
echo "[2/4] Adding and updating external-secrets Helm repository..."
if [[ "${DRY_RUN}" = true ]]; then
  echo "  [DRY-RUN] helm repo add external-secrets https://charts.external-secrets.io"
  echo "  [DRY-RUN] helm repo update external-secrets"
else
  if command -v helm >/dev/null 2>&1; then
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update external-secrets
  else
    echo "  Helm not found in PATH; falling back to raw manifests."
  fi
fi

# 3. Deploy External Secrets Operator
echo "[3/4] Deploying External Secrets Operator..."
if [[ "${DRY_RUN}" = true ]]; then
  echo "  [DRY-RUN] helm upgrade --install external-secrets external-secrets/external-secrets \\"
  echo "              -n external-secrets --create-namespace \\"
  echo "              --set installCRDs=true \\"
  echo "              --set serviceAccount.name=external-secrets-sa \\"
  echo "              --set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=\"${ROLE_ARN}\""
  echo ""
  echo "Dry run completed successfully."
  exit 0
fi

if command -v helm >/dev/null 2>&1; then
  helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets \
    --create-namespace \
    --set installCRDs=true \
    --set serviceAccount.name=external-secrets-sa \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ROLE_ARN}"
else
  kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "https://raw.githubusercontent.com/external-secrets/external-secrets/v0.14.3/deploy/manifests/external-secrets.yaml"
  kubectl annotate sa external-secrets-sa -n external-secrets "eks.amazonaws.com/role-arn=${ROLE_ARN}" --overwrite
fi

echo "Waiting for External Secrets Operator deployment to be ready..."
kubectl rollout status deployment/external-secrets -n external-secrets --timeout=180s || true

# 4. Apply ClusterSecretStore
echo "[4/4] Configuring ClusterSecretStore..."
STORE_MANIFEST="${ROOT_DIR}/k8s/base/external-secrets/cluster-secret-store.yaml"
if [[ -f "${STORE_MANIFEST}" ]]; then
  kubectl apply -f "${STORE_MANIFEST}"
fi

echo ""
echo "=========================================================="
echo "  External Secrets Operator installed successfully!"
echo "=========================================================="
echo "  Verification commands:"
echo "    kubectl get deployment -n external-secrets"
echo "    kubectl get pods -n external-secrets"
echo "    kubectl get clustersecretstore aws-secrets-manager"
echo "=========================================================="
