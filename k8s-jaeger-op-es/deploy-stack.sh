#!/bin/bash
# deploy-stack.sh - Deploy the complete Jaeger + Elasticsearch stack
echo "🔍 Step 4: Deploying Jaeger Instance with OTLP Support..."
echo "======================================================="

echo ""
echo "� Deployment Plan:"
echo "  1. Install cert-manager"
echo "  2. Install Jaeger Operator"
echo "  3. Deploy Elasticsearch"
echo "  4. Deploy Jaeger Instance with OTLP Support"
echo "  5. Verify deployment + Elasticsearch stack"

set -e

echo "🚀 Deploying Jaeger + OpenTelemetry + Elasticsearch Stack"
echo "========================================================="

# Check if cluster is running
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Kubernetes cluster is not accessible. Please ensure kind cluster is running."
    echo "   Run: ./create-kind-cluster.sh"
    exit 1
fi

echo ""
echo "🔧 Step 1: Installing cert-manager (required for Jaeger Operator)..."
echo "=================================================================="

# Check if cert-manager is already installed
if ! kubectl get namespace cert-manager &>/dev/null; then
    echo "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

    echo "Waiting for cert-manager to be ready..."
    kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s
    echo "✅ cert-manager installed successfully!"
else
    echo "✅ cert-manager already installed"
fi

echo ""
echo "🔧 Step 2: Installing Jaeger Operator..."
echo "========================================"

# Create observability namespace if it doesn't exist
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# Install Jaeger Operator
echo "Installing Jaeger Operator..."
# Operator manifest from https://github.com/jaegertracing/jaeger-operator/releases/download/v1.60.0/jaeger-operator.yaml
kubectl apply -f k8s-manifests/jaeger-operator.yaml

echo "Waiting for Jaeger Operator to be ready..."
kubectl wait --for=condition=available deployment/jaeger-operator -n observability --timeout=300s

echo "✅ Jaeger Operator installed successfully!"

echo ""
echo "🗄️  Step 3: Deploying Elasticsearch..."
echo "======================================"

kubectl apply -f k8s-manifests/elasticsearch.yaml

echo "Waiting for Elasticsearch StatefulSet to be ready..."
kubectl wait --for=condition=ready pod -l app=elasticsearch -n elasticsearch --timeout=300s

echo "Waiting for Elasticsearch setup job to complete..."
kubectl wait --for=condition=complete job/elasticsearch-setup -n elasticsearch --timeout=120s

echo "✅ Elasticsearch deployed and configured!"

echo ""
echo "� Step 3: Deploying Jaeger Instance with OTLP Support..."
echo "======================================="

kubectl apply -f k8s-manifests/jaeger-instance-simple.yaml
kubectl apply -f k8s-manifests/jaeger-nodeport-services.yaml

echo "Waiting for Jaeger components to be ready..."
# Wait for collector
until kubectl get deployment/jaeger-otel-collector -n observability &>/dev/null; do
    echo "⏳ Waiting for jaeger-otel-collector deployment to be created..."
    sleep 5
done
kubectl wait --for=condition=available deployment/jaeger-otel-collector -n observability --timeout=300s

# Wait for query
until kubectl get deployment/jaeger-otel-query -n observability &>/dev/null; do
    echo "⏳ Waiting for jaeger-otel-query deployment to be created..."
    sleep 5
done
kubectl wait --for=condition=available deployment/jaeger-otel-query -n observability --timeout=300s

echo "✅ Jaeger instance deployed successfully!"

echo ""
echo "🔍 Step 5: Verifying deployment..."
echo "================================="

echo ""
echo "📊 Cluster Status:"
echo "------------------"
kubectl get nodes -o wide

echo ""
echo "🏷️  Namespaces:"
echo "---------------"
kubectl get ns | grep -E "(elasticsearch|observability|default)"

echo ""
echo "📦 Pods Status:"
echo "---------------"
echo "Elasticsearch:"
kubectl get pods -n elasticsearch -o wide

echo ""
echo "Jaeger:"
kubectl get pods -l app=jaeger -o wide

echo ""
echo "Jaeger OTLP Collectors:"
kubectl get pods -n observability -l app.kubernetes.io/component=collector -o wide

echo ""
echo "🌐 Services:"
echo "------------"
echo "External access (NodePort services):"
kubectl get svc -o wide | grep NodePort

echo ""
echo "🔍 Jaeger Resources:"
echo "-------------------"
kubectl get jaeger -o wide

echo ""
echo "🎯 Access Points:"
echo "================="

echo "  📊 Jaeger UI:           http://localhost:16686/jaeger"
echo "  📡 OTLP (Jaeger):       localhost:4317 (gRPC), localhost:4318 (HTTP)"
echo "  🗄️ Elasticsearch:       localhost:9200"

echo ""
echo "🧪 Quick Test Commands:"
echo "======================="
echo "# Send trace to Jaeger OTLP endpoint:"
echo "otel-cli span --endpoint http://localhost:4318 --service test-service --name test-span"
echo ""
echo "# Run end-to-end test:"
echo "./simple-trace-test.sh"
echo ""
echo "# Check Jaeger services:"
echo "curl -s http://localhost:16686/jaeger/api/services | jq ."

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "🔧 Troubleshooting:"
echo "==================="
echo "# View logs:"
echo "kubectl logs -l app=elasticsearch -n elasticsearch"
echo "kubectl logs -l app=jaeger -n observability"
echo ""
echo "# Check resource usage:"
echo "kubectl top nodes"
echo "kubectl top pods --all-namespaces"
echo ""
