#!/usr/bin/env bash
set -euo pipefail

#
# build-push-initial.sh — First-time manual build of all 8 Docker images
#                         from the application repo and push them to ECR.
#
# Usage:
#   ./scripts/build-push-initial.sh [dev|prod] [region] [tag]
#   ./scripts/build-push-initial.sh --env dev --region us-east-1 --tag v1.0.0
#
# Technical Spec Reference:
#   - Section 6: ECR Container Registry
#   - Section 17: Application Services & Docker Build
#

ENV="dev"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TAG="v1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_REPO_DIR="${APP_REPO_DIR:-}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --app-dir)
      APP_REPO_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [options] or $0 [env] [region] [tag]"
      echo ""
      echo "Options:"
      echo "  --env <dev|prod>      Target environment (default: dev)"
      echo "  --region <region>     AWS region (default: us-east-1 or \$AWS_DEFAULT_REGION)"
      echo "  --tag <tag>           Image tag (default: v1.0.0)"
      echo "  --app-dir <path>      Path to spring-petclinic-microservices repository"
      echo "  -h, --help            Show this help message"
      exit 0
      ;;
    dev|prod)
      ENV="$1"
      shift
      ;;
    *)
      if [[ -z "${2:-}" && "$1" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
        REGION="$1"
      elif [[ -z "${3:-}" && "$1" =~ ^v[0-9]+ ]]; then
        TAG="$1"
      else
        echo "Unknown option: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "Error: environment must be 'dev' or 'prod' (received: $ENV)" >&2
  exit 1
fi

# Locate the application repository
if [[ -z "$APP_REPO_DIR" ]]; then
  CANDIDATE_PATHS=(
    "$SCRIPT_DIR/../../spring-petclinic-microservices"
    "/c/Project/AIdevops/spring-petclinic-microservices"
    "/c/project/AIdevops/spring-petclinic-microservices"
    "C:/Project/AIdevops/spring-petclinic-microservices"
    "C:/project/AIdevops/spring-petclinic-microservices"
  )
  for path in "${CANDIDATE_PATHS[@]}"; do
    if [[ -d "$path" && -f "$path/pom.xml" ]]; then
      APP_REPO_DIR="$path"
      break
    fi
  done
fi

if [[ -z "$APP_REPO_DIR" || ! -d "$APP_REPO_DIR" ]]; then
  echo "Error: spring-petclinic-microservices repository not found." >&2
  echo "Please set APP_REPO_DIR environment variable or pass --app-dir <path>." >&2
  exit 1
fi

echo "=========================================================="
echo " Petclinic Platform - Initial Docker Build & ECR Push"
echo " Environment : $ENV"
echo " Region      : $REGION"
echo " Tag         : $TAG"
echo " App Repo    : $APP_REPO_DIR"
echo "=========================================================="

echo "Building Maven JARs in $APP_REPO_DIR..."
cd "$APP_REPO_DIR"

if [[ -f "./mvnw" ]]; then
  ./mvnw clean package -DskipTests
elif [[ -f "./mvnw.cmd" ]]; then
  cmd.exe /c mvnw.cmd clean package -DskipTests
else
  mvn clean package -DskipTests
fi

echo "Fetching AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ -z "$ACCOUNT_ID" ]]; then
  echo "Error: Could not determine AWS Account ID. Please configure AWS credentials." >&2
  exit 1
fi

REGISTRY_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ECR: ${REGISTRY_URL}..."
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"

# Define 8 services as per docs/technical-spec.md
SERVICES=(
  "config-server:spring-petclinic-config-server:8888"
  "discovery-server:spring-petclinic-discovery-server:8761"
  "api-gateway:spring-petclinic-api-gateway:8080"
  "customers-service:spring-petclinic-customers-service:8081"
  "visits-service:spring-petclinic-visits-service:8082"
  "vets-service:spring-petclinic-vets-service:8083"
  "genai-service:spring-petclinic-genai-service:8084"
  "admin-server:spring-petclinic-admin-server:9090"
)

for entry in "${SERVICES[@]}"; do
  IFS=":" read -r SVC_NAME MODULE_NAME PORT <<< "$entry"

  echo "----------------------------------------------------------"
  echo "Building and pushing: ${SVC_NAME} (module: ${MODULE_NAME}, port: ${PORT})"
  echo "----------------------------------------------------------"

  TARGET_DIR="${APP_REPO_DIR}/${MODULE_NAME}/target"
  
  # Find the executable JAR artifact, excluding javadoc and sources
  JAR_FILE=$(find "$TARGET_DIR" -maxdepth 1 -name "${MODULE_NAME}-*.jar" ! -name "*-javadoc.jar" ! -name "*-sources.jar" 2>/dev/null | head -n 1)

  if [[ -z "$JAR_FILE" || ! -f "$JAR_FILE" ]]; then
    echo "Error: JAR file not found for ${SVC_NAME} in ${TARGET_DIR}" >&2
    exit 1
  fi

  JAR_BASENAME=$(basename "$JAR_FILE")
  ARTIFACT_NAME="${JAR_BASENAME%.jar}"
  REPO="petclinic-${ENV}/${SVC_NAME}"
  IMAGE_URL="${REGISTRY_URL}/${REPO}:${TAG}"

  echo "Artifact   : ${ARTIFACT_NAME}"
  echo "Image URI  : ${IMAGE_URL}"

  # Build for linux/arm64 as required for Graviton t4g nodes in technical-spec.md
  docker buildx build --platform linux/arm64 \
    --build-arg ARTIFACT_NAME="${ARTIFACT_NAME}" \
    --build-arg EXPOSED_PORT="${PORT}" \
    -f "${APP_REPO_DIR}/docker/Dockerfile" \
    -t "${IMAGE_URL}" \
    --push \
    "${TARGET_DIR}"

  echo "Successfully built and pushed ${IMAGE_URL}"
done

echo "=========================================================="
echo "All 8 Petclinic images built and pushed successfully!"
echo "Registry: ${REGISTRY_URL}"
echo "Tag     : ${TAG}"
echo "=========================================================="
