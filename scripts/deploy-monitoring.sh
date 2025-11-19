#!/bin/bash
set -e

echo "📊 Deploying Monitoring Stack..."

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed."; exit 1; }

# Create namespaces
echo "📦 Creating namespaces..."
kubectl apply -f k8s/namespace.yaml

# Deploy Prometheus
echo "🔍 Deploying Prometheus..."
kubectl apply -f alerts/prometheus-rules.yaml
kubectl apply -f k8s/prometheus/

# Wait for Prometheus
echo "⏳ Waiting for Prometheus to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring

# Deploy Grafana
echo "📈 Deploying Grafana..."
kubectl apply -f k8s/grafana/

# Wait for Grafana
echo "⏳ Waiting for Grafana to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring

# Deploy AlertManager
echo "🚨 Deploying AlertManager..."
kubectl apply -f k8s/alertmanager/

# Wait for AlertManager
echo "⏳ Waiting for AlertManager to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/alertmanager -n monitoring

# Deploy Exporters
echo "📡 Deploying Exporters..."
kubectl apply -f k8s/exporters/

echo "✅ Monitoring stack deployment complete!"
echo ""
echo "Access dashboards:"
echo "  Grafana:       kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo "  Prometheus:    kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo "  AlertManager:  kubectl port-forward -n monitoring svc/alertmanager 9093:9093"
