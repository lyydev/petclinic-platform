#!/bin/bash
set -e

# Default to us-east-1 as per overarching project rules
REGION="${1:-us-east-1}"

echo "Fetching AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "123456789012")

if [ -z "$ACCOUNT_ID" ]; then
    echo "Failed to fetch AWS Account ID. Please ensure you are authenticated."
    exit 1
fi

BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="petclinic-terraform-locks"

echo "Using region: $REGION"
echo "Bucket name: $BUCKET_NAME"
echo "Table name: $TABLE_NAME"

# Create S3 Bucket
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "Bucket $BUCKET_NAME already exists."
else
    echo "Creating bucket $BUCKET_NAME..."
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION"
    fi
fi

# Enable versioning
echo "Enabling versioning..."
aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled

# Enable encryption
echo "Enabling encryption..."
aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block public access
echo "Blocking public access..."
aws s3api put-public-access-block --bucket "$BUCKET_NAME" --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "DynamoDB table $TABLE_NAME already exists."
else
    echo "Creating DynamoDB table $TABLE_NAME..."
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION"
fi

echo "Bootstrap complete."
