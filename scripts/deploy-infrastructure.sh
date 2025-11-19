#!/bin/bash
set -e

echo "🚀 Deploying ShopMetrics Infrastructure..."

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform is required but not installed."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed."; exit 1; }

# Set variables
export AWS_REGION=${AWS_REGION:-us-east-1}
export ENVIRONMENT=${ENVIRONMENT:-production}

echo "📍 Region: $AWS_REGION"
echo "🏷️  Environment: $ENVIRONMENT"

# Initialize Terraform
cd terraform
echo "🔧 Initializing Terraform..."
terraform init

# Plan infrastructure
echo "📋 Planning infrastructure changes..."
terraform plan -out=tfplan

# Apply infrastructure
read -p "Apply these changes? (yes/no): " confirm
if [ "$confirm" == "yes" ]; then
    echo "🏗️  Creating infrastructure..."
    terraform apply tfplan
    
    # Get outputs
    echo "📤 Getting cluster information..."
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    
    # Configure kubectl
    echo "⚙️  Configuring kubectl..."
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
    
    echo "✅ Infrastructure deployment complete!"
    echo "Cluster: $CLUSTER_NAME"
else
    echo "❌ Deployment cancelled"
    exit 1
fi

cd ..
