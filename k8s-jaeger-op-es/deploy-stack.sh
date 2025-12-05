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
echo "  5. Deploy Traces Dashboard"
echo "  6. Verify deployment + Elasticsearch stack"

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
echo "🔧 Step 2: Installing Jaeger..."
echo "========================================"

# Create observability namespace if it doesn't exist
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# Install Jaeger
echo "Installing Jaeger using kubectl..."
kubectl apply -f k8s-manifests/jaeger-v2-deployment.yaml

echo "Waiting for Jaeger to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=jaeger -n observability --timeout=60s

echo "✅ Jaeger installed successfully!"

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
echo "📊 Step 5: Deploying Traces Dashboard..."
echo "========================================"

kubectl apply -f k8s-manifests/dashboard.yaml

echo "Waiting for dashboard to be ready..."
kubectl wait --for=condition=ready pod -l app=traces-dashboard -n traces-dashboard --timeout=60s

echo "✅ Traces Dashboard deployed successfully!"

echo ""
echo "🔍 Step 6: Verifying deployment..."
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
kubectl get pods -l app=jaeger-v2 -o wide

echo ""
echo "🌐 Services:"
echo "------------"
echo "External access (NodePort services):"
kubectl get svc -o wide | grep NodePort

echo ""
echo "🎯 Access Points:"
echo "================="

echo "  📊 Jaeger UI:           http://localhost:16686/jaeger"
echo "  📈 Traces Dashboard:    http://localhost:30080"
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
