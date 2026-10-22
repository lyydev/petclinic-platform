#!/usr/bin/env bash
set -euo pipefail

#
# ecr-login.sh — Authenticate Docker to AWS ECR private registry
#
# Usage:
#   ./scripts/ecr-login.sh [--region <region>]
#   ./scripts/ecr-login.sh [region]
#

REGION="${AWS_DEFAULT_REGION:-us-east-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--region <region>]"
      echo "Defaults to region 'us-east-1' or \$AWS_DEFAULT_REGION"
      exit 0
      ;;
    *)
      # Fallback to positional argument if provided
      REGION="$1"
      shift
      ;;
  esac
done

echo "Fetching AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [[ -z "${ACCOUNT_ID}" ]]; then
  echo "Error: Failed to obtain AWS Account ID. Please verify your AWS credentials." >&2
  exit 1
fi

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ECR registry: ${REGISTRY} (region: ${REGION})..."
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

echo "ECR login successful."
