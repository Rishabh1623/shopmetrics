#!/bin/bash
# Script to create Terraform backend resources (S3 + DynamoDB)
# Run this ONCE before running terraform init

set -e

# Configuration
BUCKET_NAME="shopmetrics-terraform-state"
DYNAMODB_TABLE="terraform-state-lock"
AWS_REGION="us-east-1"

echo "🚀 Creating Terraform backend resources..."

# Create S3 bucket for state
echo "📦 Creating S3 bucket: $BUCKET_NAME"
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION 2>/dev/null || echo "Bucket already exists"

# Enable versioning on the bucket
echo "🔄 Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption
echo "🔒 Enabling encryption..."
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
echo "🛡️  Blocking public access..."
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table for state locking
echo "🔐 Creating DynamoDB table: $DYNAMODB_TABLE"
aws dynamodb create-table \
  --table-name $DYNAMODB_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION 2>/dev/null || echo "Table already exists"

echo ""
echo "✅ Terraform backend resources created successfully!"
echo ""
echo "📝 Backend configuration:"
echo "   S3 Bucket: $BUCKET_NAME"
echo "   DynamoDB Table: $DYNAMODB_TABLE"
echo "   Region: $AWS_REGION"
echo ""
echo "You can now run: cd ../terraform && terraform init"
