#!/bin/bash
# cleanup-stack.sh - Clean up the Jaeger + OTEL + Elasticsearch stack

set -e

echo "🧹 Cleaning up Jaeger + OTEL + Elasticsearch Stack"
echo "=================================================="

# Check if cluster is running
if ! kubectl cluster-info &>/dev/null; then
    echo "⚠️  Kubernetes cluster is not accessible."
    echo "   Nothing to clean up."
    exit 0
fi

echo ""
echo "📋 Cleanup Plan:"
echo "  1. Delete Jaeger instances"
echo "  2. Delete OTEL Collector"
echo "  3. Delete Elasticsearch"
echo "  4. Delete Jaeger Operator"
echo "  5. Clean up namespaces"
echo ""

read -p "Continue with cleanup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "🔍 Step 1: Deleting Jaeger instances..."
echo "======================================="

if kubectl get jaeger jaeger-otel -n observability &>/dev/null; then
    kubectl delete -f k8s-manifests/jaeger-instance-simple.yaml --timeout=300s
    kubectl delete -f k8s-manifests/jaeger-nodeport-services.yaml --timeout=300s
    echo "✅ Jaeger instance deleted"
else
    echo "ℹ️  No Jaeger instance found"
fi

echo ""
echo "🔄 Step 2: Skipping standalone OTEL Collector (using Jaeger-managed collector)..."
echo "=================================================================================="

if false; then  # Disabled since we're not using standalone collector
    echo "✅ OTEL Collector deleted"
else
    echo "ℹ️  OTEL Collector not found"
fi

echo ""
echo "🗄️  Step 3: Deleting Elasticsearch..."
echo "===================================="

if kubectl get namespace elasticsearch &>/dev/null; then
    kubectl delete -f k8s-manifests/elasticsearch.yaml --timeout=300s
    echo "✅ Elasticsearch deleted"
else
    echo "ℹ️  Elasticsearch namespace not found"
fi

echo ""
echo "🔧 Step 4: Deleting Jaeger Operator..."
echo "======================================"

if kubectl get namespace observability &>/dev/null; then
    echo "Deleting Jaeger Operator..."
    kubectl delete -f k8s-manifests/jaeger-operator.yaml --timeout=300s
    echo "✅ Jaeger Operator deleted"
else
    echo "ℹ️  Observability namespace not found"
fi

echo ""
echo "🧹 Step 5: Cleaning up namespaces..."
echo "==================================="

# Delete namespaces (they should be empty now)
for ns in elasticsearch observability; do
    if kubectl get namespace $ns &>/dev/null; then
        echo "Deleting namespace: $ns"
        kubectl delete namespace $ns --timeout=120s
    fi
done

echo ""
echo "🔍 Verifying cleanup..."
echo "======================"

echo ""
echo "📦 Remaining pods in default namespace:"
kubectl get pods -o wide || echo "No pods found"

echo ""
echo "🌐 Remaining services in default namespace:"
kubectl get svc -o wide || echo "No services found"

echo ""
echo "🏷️  Remaining namespaces:"
kubectl get ns | grep -E "(elasticsearch|observability)" || echo "Target namespaces cleaned up"

echo ""
echo "💾 Persistent volumes:"
kubectl get pv | grep -E "(elasticsearch|jaeger)" || echo "No relevant PVs found"

echo ""
echo "🎉 Cleanup completed!"
echo ""
echo "ℹ️  Note: The kind cluster is still running."
echo "   To delete the cluster completely, run: ./delete-kind-cluster.sh"