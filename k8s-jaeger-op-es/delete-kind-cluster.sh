#!/bin/bash
# delete-kind-cluster.sh - Clean up the kind cluster

set -e

CLUSTER_NAME="jaeger-otel-cluster"

echo "🧹 Deleting kind cluster: $CLUSTER_NAME"
echo "======================================="

# Delete the cluster
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "Deleting cluster..."
    kind delete cluster --name "$CLUSTER_NAME"
    echo "✅ Cluster deleted successfully!"
else
    echo "⚠️  Cluster '$CLUSTER_NAME' does not exist"
fi

echo ""
echo "🎉 Cleanup complete!"