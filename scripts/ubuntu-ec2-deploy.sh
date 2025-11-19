#!/bin/bash
# ============================================================================
# Complete Deployment Script for Ubuntu EC2
# Run this script on a fresh Ubuntu EC2 instance
# ============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# ============================================================================
# Part 1: Install Required Tools
# ============================================================================

install_tools() {
    log_info "Installing required tools..."
    
    # Update system
    sudo apt update && sudo apt upgrade -y
    
    # Install AWS CLI
    if ! command -v aws &> /dev/null; then
        log_info "Installing AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        sudo apt install unzip -y
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    fi
    
    # Install Terraform
    if ! command -v terraform &> /dev/null; then
        log_info "Installing Terraform..."
        sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update
        sudo apt-get install terraform -y
    fi
    
    # Install kubectl
    if ! command -v kubectl &> /dev/null; then
        log_info "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi
    
    # Install Git
    if ! command -v git &> /dev/null; then
        log_info "Installing Git..."
        sudo apt install git -y
    fi
    
    # Install PostgreSQL client
    if ! command -v psql &> /dev/null; then
        log_info "Installing PostgreSQL client..."
        sudo apt install postgresql-client -y
    fi
    
    log_info "All tools installed successfully!"
}

# ============================================================================
# Part 2: Configure AWS
# ============================================================================

configure_aws() {
    log_info "Configuring AWS..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_warn "AWS credentials not configured"
        echo "Please run: aws configure"
        exit 1
    fi
    
    log_info "AWS credentials verified"
}

# ============================================================================
# Part 3: Create Project Structure
# ============================================================================

create_project_structure() {
    log_info "Creating project structure..."
    
    mkdir -p ~/projects/shopmetrics
    cd ~/projects/shopmetrics
    
    mkdir -p terraform/bootstrap
    mkdir -p k8s/{prometheus,grafana,alertmanager,exporters}
    mkdir -p shopmetrics/{services,frontend,monitoring}
    mkdir -p database/schemas
    mkdir -p scripts
    mkdir -p docs
    mkdir -p alerts
    mkdir -p dashboards
    
    log_info "Project structure created"
}

# ============================================================================
# Part 4: Create Terraform Backend
# ============================================================================

create_backend() {
    log_info "Creating Terraform backend..."
    
    cd ~/projects/shopmetrics/terraform/bootstrap
    
    cat > create-backend.sh << 'EOF'
#!/bin/bash
set -e

BUCKET_NAME="shopmetrics-terraform-state"
DYNAMODB_TABLE="terraform-state-lock"
AWS_REGION="us-east-1"

echo "Creating Terraform backend..."

aws s3api create-bucket --bucket $BUCKET_NAME --region $AWS_REGION 2>/dev/null || echo "Bucket exists"
aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket $BUCKET_NAME --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket $BUCKET_NAME --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
aws dynamodb create-table --table-name $DYNAMODB_TABLE --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region $AWS_REGION 2>/dev/null || echo "Table exists"

echo "✓ Backend created successfully!"
EOF
    
    chmod +x create-backend.sh
    ./create-backend.sh
    
    log_info "Terraform backend created"
}

# ============================================================================
# Part 5: Create Terraform Configuration
# ============================================================================

create_terraform_config() {
    log_info "Creating Terraform configuration..."
    
    cd ~/projects/shopmetrics/terraform
    
    # Copy main-consolidated.tf to main.tf
    # (Assuming the file exists in the project)
    
    # Create variables.tf
    cat > variables.tf << 'EOF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "shopmetrics"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "production"
}

variable "node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 3
}
EOF
    
    log_info "Terraform configuration created"
}

# ============================================================================
# Part 6: Deploy Infrastructure
# ============================================================================

deploy_infrastructure() {
    log_info "Deploying infrastructure..."
    
    cd ~/projects/shopmetrics/terraform
    
    terraform init
    terraform plan -out=tfplan
    
    read -p "Apply infrastructure? (yes/no): " confirm
    if [ "$confirm" == "yes" ]; then
        terraform apply tfplan
        log_info "Infrastructure deployed successfully"
    else
        log_warn "Infrastructure deployment cancelled"
        exit 1
    fi
}

# ============================================================================
# Part 7: Configure kubectl
# ============================================================================

configure_kubectl() {
    log_info "Configuring kubectl..."
    
    cd ~/projects/shopmetrics/terraform
    
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-1
    
    kubectl get nodes
    
    log_info "kubectl configured successfully"
}

# ============================================================================
# Part 8: Deploy Monitoring
# ============================================================================

deploy_monitoring() {
    log_info "Deploying monitoring stack..."
    
    cd ~/projects/shopmetrics
    
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/prometheus/
    kubectl apply -f k8s/grafana/
    kubectl apply -f k8s/alertmanager/
    kubectl apply -f k8s/exporters/
    
    log_info "Waiting for monitoring pods..."
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring || true
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring || true
    
    log_info "Monitoring stack deployed"
}

# ============================================================================
# Part 9: Deploy Application
# ============================================================================

deploy_application() {
    log_info "Deploying application..."
    
    cd ~/projects/shopmetrics
    
    kubectl apply -f shopmetrics/secrets.yaml
    kubectl apply -f shopmetrics/services/
    kubectl apply -f shopmetrics/frontend/
    
    log_info "Application deployed"
}

# ============================================================================
# Part 10: Show Access Info
# ============================================================================

show_access_info() {
    log_info "Deployment complete!"
    echo ""
    echo "========================================="
    echo "Access your services:"
    echo "========================================="
    echo ""
    echo "1. Port forward services:"
    echo "   kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo "   kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    echo ""
    echo "2. From your local machine, create SSH tunnel:"
    echo "   ssh -i your-key.pem -L 3000:localhost:3000 -L 9090:localhost:9090 ubuntu@<EC2-IP>"
    echo ""
    echo "3. Access dashboards:"
    echo "   Grafana:    http://localhost:3000 (admin/changeme123!)"
    echo "   Prometheus: http://localhost:9090"
    echo ""
    echo "4. Check status:"
    echo "   kubectl get pods -A"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo "========================================="
    echo "ShopMetrics Ubuntu EC2 Deployment"
    echo "========================================="
    echo ""
    
    install_tools
    configure_aws
    create_project_structure
    create_backend
    create_terraform_config
    deploy_infrastructure
    configure_kubectl
    deploy_monitoring
    deploy_application
    show_access_info
}

# Run main function
main
