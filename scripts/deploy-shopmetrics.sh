#!/bin/bash
set -e

echo "🛒 Deploying ShopMetrics Application..."

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed."; exit 1; }

# Create secrets (update with actual values in production)
echo "🔐 Creating secrets..."
kubectl apply -f shopmetrics/secrets.yaml

# Deploy services
echo "🚀 Deploying microservices..."
kubectl apply -f shopmetrics/services/product-service.yaml
kubectl apply -f shopmetrics/services/user-service.yaml
kubectl apply -f shopmetrics/services/payment-service.yaml
kubectl apply -f shopmetrics/services/order-service.yaml

# Deploy frontend
echo "🎨 Deploying frontend..."
kubectl apply -f shopmetrics/frontend/

# Deploy monitoring configuration
echo "📊 Deploying monitoring configuration..."
kubectl apply -f shopmetrics/monitoring/

# Wait for deployments
echo "⏳ Waiting for services to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/product-service -n shopmetrics
kubectl wait --for=condition=available --timeout=300s deployment/user-service -n shopmetrics
kubectl wait --for=condition=available --timeout=300s deployment/payment-service -n shopmetrics
kubectl wait --for=condition=available --timeout=300s deployment/order-service -n shopmetrics
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n shopmetrics

echo "✅ ShopMetrics application deployment complete!"
echo ""
echo "Check status:"
echo "  kubectl get pods -n shopmetrics"
echo "  kubectl get svc -n shopmetrics"
