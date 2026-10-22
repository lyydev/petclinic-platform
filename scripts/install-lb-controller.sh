#!/usr/bin/env bash
set -euo pipefail

#
# install-lb-controller.sh — Install AWS Load Balancer Controller on EKS via Helm
#
# Usage:
#   ./scripts/install-lb-controller.sh [dev|prod]
#   ./scripts/install-lb-controller.sh --env dev --region us-east-1
#   ./scripts/install-lb-controller.sh --help
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV="dev"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CLUSTER_NAME=""
ROLE_ARN=""
VPC_ID=""
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
  --role-arn <arn>     AWS Load Balancer Controller IRSA Role ARN (auto-detected if omitted)
  --vpc-id <id>        VPC ID (auto-detected if omitted)
  --dry-run            Simulate installation and print commands without executing mutating actions
  -h, --help           Show this help message

Examples:
  $0 dev
  $0 prod --region us-east-1
  $0 --env dev --role-arn arn:aws:iam::123456789012:role/petclinic-dev-lb-controller-role
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
    --vpc-id)
      VPC_ID="$2"
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
echo "  AWS Load Balancer Controller Installation"
echo "=========================================================="
echo "  Environment:  ${ENV}"
echo "  Region:       ${REGION}"
echo "  Cluster:      ${CLUSTER_NAME}"
echo "=========================================================="
echo ""

# 1. Resolve IRSA Role ARN
if [[ -z "${ROLE_ARN}" ]]; then
  echo "[1/5] Resolving IRSA role ARN for AWS Load Balancer Controller..."
  
  # Try Terraform output first
  TF_ENV_DIR="${ROOT_DIR}/terraform/environments/${ENV}"
  if [[ -d "${TF_ENV_DIR}" ]]; then
    ROLE_ARN=$(terraform -chdir="${TF_ENV_DIR}" output -raw lb_controller_role_arn 2>/dev/null || true)
  fi

  # Fallback to AWS IAM query if Terraform output is empty
  if [[ -z "${ROLE_ARN}" ]]; then
    ROLE_NAME="petclinic-${ENV}-lb-controller-role"
    ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text 2>/dev/null || true)
  fi

  # Fallback to deriving from STS caller identity
  if [[ -z "${ROLE_ARN}" ]]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
    if [[ -n "${ACCOUNT_ID}" ]]; then
      ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/petclinic-${ENV}-lb-controller-role"
    fi
  fi
fi

if [[ -z "${ROLE_ARN}" ]]; then
  echo "Error: Unable to determine IRSA role ARN. Please provision Terraform or pass --role-arn."
  exit 1
fi
echo "  -> IRSA Role ARN: ${ROLE_ARN}"

# 2. Resolve VPC ID
if [[ -z "${VPC_ID}" ]]; then
  echo "[2/5] Resolving VPC ID for cluster ${CLUSTER_NAME}..."
  TF_ENV_DIR="${ROOT_DIR}/terraform/environments/${ENV}"
  if [[ -d "${TF_ENV_DIR}" ]]; then
    VPC_ID=$(terraform -chdir="${TF_ENV_DIR}" output -raw vpc_id 2>/dev/null || true)
  fi

  if [[ -z "${VPC_ID}" ]]; then
    VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null || true)
  fi
fi
if [[ -n "${VPC_ID}" ]]; then
  echo "  -> VPC ID: ${VPC_ID}"
else
  echo "  -> VPC ID: (auto-detected by controller at runtime)"
fi

# 3. Apply CRDs
echo "[3/5] Installing/Updating AWS Load Balancer Controller CRDs..."
if [[ "${DRY_RUN}" = true ]]; then
  echo "  [DRY-RUN] kubectl apply -k github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
else
  if ! kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master" 2>/dev/null; then
    echo "  Applying CRDs via raw manifest fallback..."
    kubectl apply -f "https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml"
  fi
  echo "  -> CRDs installed successfully."
fi

# 4. Add & update Helm repo
echo "[4/5] Adding and updating eks-charts Helm repository..."
if [[ "${DRY_RUN}" = true ]]; then
  echo "  [DRY-RUN] helm repo add eks https://aws.github.io/eks-charts"
  echo "  [DRY-RUN] helm repo update eks"
else
  helm repo add eks https://aws.github.io/eks-charts
  helm repo update eks
fi

# 5. Helm install / upgrade
echo "[5/5] Deploying AWS Load Balancer Controller to kube-system namespace..."

HELM_SET_ARGS=(
  --set clusterName="${CLUSTER_NAME}"
  --set serviceAccount.create=true
  --set serviceAccount.name=aws-load-balancer-controller
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ROLE_ARN}"
  --set region="${REGION}"
)

if [[ -n "${VPC_ID}" ]]; then
  HELM_SET_ARGS+=(--set vpcId="${VPC_ID}")
fi

if [[ "${DRY_RUN}" = true ]]; then
  echo "  [DRY-RUN] helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \\"
  echo "              -n kube-system \\"
  for arg in "${HELM_SET_ARGS[@]}"; do
    echo "              ${arg} \\"
  done
  echo ""
  echo "Dry run completed successfully."
  exit 0
fi

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  "${HELM_SET_ARGS[@]}"

echo ""
echo "Waiting for AWS Load Balancer Controller deployment to be ready..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s || true

# Apply IngressClass if not created automatically
if ! kubectl get ingressclass alb >/dev/null 2>&1; then
  echo "Creating IngressClass 'alb'..."
  if [[ -f "${ROOT_DIR}/k8s/base/ingress/ingress-class.yaml" ]]; then
    kubectl apply -f "${ROOT_DIR}/k8s/base/ingress/ingress-class.yaml"
  fi
fi

echo ""
echo "=========================================================="
echo "  AWS Load Balancer Controller installed successfully!"
echo "=========================================================="
echo "  Verification commands:"
echo "    kubectl get deployment -n kube-system aws-load-balancer-controller"
echo "    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
echo "    kubectl get ingressclass alb"
echo "=========================================================="
