#!/bin/bash
set -e

echo "🧹 Cleaning up ShopMetrics deployment..."

read -p "This will delete all resources. Are you sure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Cleanup cancelled"
    exit 1
fi

# Delete application
echo "🗑️  Deleting ShopMetrics application..."
kubectl delete namespace shopmetrics --ignore-not-found=true

# Delete monitoring stack
echo "🗑️  Deleting monitoring stack..."
kubectl delete namespace monitoring --ignore-not-found=true

# Destroy infrastructure
echo "🗑️  Destroying infrastructure..."
cd terraform
terraform destroy -auto-approve

echo "✅ Cleanup complete!"
