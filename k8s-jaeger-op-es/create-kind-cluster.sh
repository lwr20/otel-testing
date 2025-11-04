#!/bin/bash
# create-kind-cluster.sh - Create and configure the 3-node kind cluster

set -e

CLUSTER_NAME="jaeger-otel-cluster"

echo "🚀 Creating 3-node kind cluster for Jaeger + OTEL..."
echo "=================================================="

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "❌ kind is not installed. Please install it first:"
    echo "   https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install it first:"
    echo "   https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
    exit 1
fi


# Delete existing cluster if it exists
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "🧹 Deleting existing cluster..."
    kind delete cluster --name "$CLUSTER_NAME"
fi

# Create the cluster
echo "🏗️  Creating kind cluster with 3 nodes..."
kind create cluster --config kind-config.yaml

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Display cluster information
echo ""
echo "✅ Cluster created successfully!"
echo ""
echo "🔍 Cluster Information:"
echo "======================"
kubectl get nodes -o wide

echo ""
echo "📋 Node Labels:"
echo "==============="
kubectl get nodes --show-labels

echo ""
echo "🎯 Cluster Access:"
echo "=================="
echo "  - Cluster Name: $CLUSTER_NAME"
echo "  - Kubeconfig: ~/.kube/config (automatically configured)"
echo "  - API Server: https://127.0.0.1:6443"

echo ""
echo "📦 Next Steps:"
echo "=============="
echo "1. Install Jaeger Operator:"
echo "   kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.60.0/jaeger-operator.yaml"
echo ""
echo "2. Deploy OTEL Collector:"
echo "   kubectl apply -f k8s-manifests/"
echo ""
echo "3. Create Jaeger instance:"
echo "   kubectl apply -f jaeger-instance.yaml"
echo ""
echo "🎉 Kind cluster is ready for Jaeger + OTEL deployment!"