#!/bin/bash
# ============================================================================
# ShopMetrics Complete Deployment Script
# AWS Best Practice: Automated, idempotent deployment
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="shopmetrics"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-production}"

# Functions
log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    command -v aws >/dev/null 2>&1 || { log_error "AWS CLI not installed"; exit 1; }
    command -v terraform >/dev/null 2>&1 || { log_error "Terraform not installed"; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { log_error "kubectl not installed"; exit 1; }
    
    aws sts get-caller-identity >/dev/null 2>&1 || { log_error "AWS credentials not configured"; exit 1; }
    
    log_info "All prerequisites met"
}

create_backend() {
    log_info "Creating Terraform backend..."
    cd terraform/bootstrap
    chmod +x create-backend.sh
    ./create-backend.sh
    cd ../..
}

deploy_infrastructure() {
    log_info "Deploying AWS infrastructure..."
    cd terraform
    
    terraform init
    terraform plan -out=tfplan
    
    read -p "Apply infrastructure changes? (yes/no): " confirm
    if [ "$confirm" == "yes" ]; then
        terraform apply tfplan
        log_info "Infrastructure deployed successfully"
    else
        log_warn "Infrastructure deployment cancelled"
        exit 1
    fi
    
    cd ..
}

configure_kubectl() {
    log_info "Configuring kubectl..."
    CLUSTER_NAME=$(cd terraform && terraform output -raw eks_cluster_name)
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
    kubectl get nodes
}

deploy_monitoring() {
    log_info "Deploying monitoring stack..."
    
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f alerts/prometheus-rules.yaml
    kubectl apply -f k8s/prometheus/
    kubectl apply -f k8s/grafana/
    kubectl apply -f k8s/alertmanager/
    kubectl apply -f k8s/exporters/
    
    log_info "Waiting for monitoring pods..."
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring
    
    log_info "Monitoring stack deployed"
}

deploy_application() {
    log_info "Deploying ShopMetrics application..."
    
    kubectl apply -f shopmetrics/secrets.yaml
    kubectl apply -f shopmetrics/services/
    kubectl apply -f shopmetrics/frontend/
    kubectl apply -f shopmetrics/monitoring/
    
    log_info "Application deployed"
}

show_access_info() {
    log_info "Deployment complete!"
    echo ""
    echo "Access your services:"
    echo "  Grafana:    kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo "  Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    echo "  Frontend:   kubectl port-forward -n shopmetrics svc/frontend 8080:80"
    echo ""
    echo "Check status:"
    echo "  kubectl get pods -n monitoring"
    echo "  kubectl get pods -n shopmetrics"
}

# Main execution
main() {
    echo "========================================="
    echo "ShopMetrics Deployment"
    echo "========================================="
    echo ""
    
    check_prerequisites
    
    # Check if backend exists
    if ! aws s3 ls s3://${PROJECT_NAME}-terraform-state >/dev/null 2>&1; then
        log_warn "Terraform backend not found"
        read -p "Create backend? (yes/no): " create_backend_confirm
        if [ "$create_backend_confirm" == "yes" ]; then
            create_backend
        else
            log_error "Backend required for deployment"
            exit 1
        fi
    fi
    
    deploy_infrastructure
    configure_kubectl
    deploy_monitoring
    deploy_application
    show_access_info
}

# Run main function
main
