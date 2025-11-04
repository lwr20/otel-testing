# Jaeger + OpenTelemetry on Kind Kubernetes

This directory contains everything needed to deploy Jaeger with OpenTelemetry collector support on a 3-node Kind cluster.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    3-Node Kind Cluster                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Control Plane │  │    Worker 1     │  │    Worker 2     │  │
│  │                 │  │                 │  │                 │  │
│  │   - API Server  │  │ - Jaeger Query  │  │ - OTEL Collector│  │
│  │   - etcd        │  │ - Elasticsearch │  │ - Jaeger Agent  │  │
│  │   - Scheduler   │  │ - Jaeger Coll.  │  │                 │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                               │
                        Port Forwarding
                               │
┌─────────────────────────────────────────────────────────────────┐
│                       Host Machine                              │
│  • Jaeger UI:       localhost:16686                             │
│  • OTLP gRPC:       localhost:4317  (direct to Jaeger)          │
│  • OTLP HTTP:       localhost:4318  (direct to Jaeger)          │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### 1. Create Kind Cluster

```bash
# Create the 3-node cluster with port mappings
./create-kind-cluster.sh
```

### 2. Install Jaeger Operator

```bash
# Install the Jaeger Operator
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.60.0/jaeger-operator.yaml

# Wait for operator to be ready
kubectl wait --for=condition=available deployment/jaeger-operator -n observability --timeout=300s
```

### 3. Deploy the Stack

```bash
# Deploy OTEL Collector
kubectl apply -f k8s-manifests/otel-collector.yaml

# Deploy Jaeger with Elasticsearch
kubectl apply -f k8s-manifests/jaeger-instance.yaml

# Wait for all components
kubectl wait --for=condition=available deployment --all --timeout=600s
```

### 4. Verify Deployment

```bash
# Check all pods
kubectl get pods -o wide

# Check services
kubectl get svc

# Check Jaeger instance
kubectl get jaeger
```

## 📊 Component Overview

### Jaeger Operator Deployment

- **Strategy**: Production (separate collector, query, agent)
- **Storage**: Elasticsearch (1 node, development setup)
- **Collector**: 2 replicas with OTLP support
- **Query**: 1 replica with NodePort exposure
- **Agent**: DaemonSet for legacy Jaeger client support

### Standalone OTEL Collector

- **Replicas**: 2 for high availability
- **Purpose**: Advanced processing, filtering, transformation
- **Features**: Prometheus metrics, Z-pages debugging, health checks
- **Node Placement**: Scheduled on worker nodes

### Storage & Persistence

- **Elasticsearch**: Embedded with Jaeger Operator
- **Index Management**: Automatic cleanup after 7 days
- **Resources**: 1Gi memory, 500m CPU requests

## 🔧 Configuration Files

### `kind-config.yaml`

- 3-node cluster: 1 control-plane + 2 workers
- Port mappings for all services
- Resource limits and node labels
- Persistent volume support

### `k8s-manifests/jaeger-instance.yaml`

- Jaeger CR with production strategy
- Elasticsearch storage configuration
- OTLP receiver configuration
- NodePort services for external access

### `k8s-manifests/otel-collector.yaml`

- Standalone OTEL Collector deployment
- ConfigMap with advanced processing pipeline
- Multiple service types (ClusterIP + NodePort)
- Health checks and resource limits

## 🎯 Access Points

After deployment, access services via:

### From Host Machine

- **Jaeger UI**: http://localhost:16686/jaeger
- **Direct OTLP (Jaeger)**: localhost:4317 (gRPC), localhost:4318 (HTTP)
- **OTEL Collector**: localhost:4320 (gRPC), localhost:4321 (HTTP)
- **Prometheus Metrics**: http://localhost:8889/metrics
- **Health Checks**: http://localhost:13133

### Inside Cluster

- **Jaeger Query**: `jaeger-otel-query:16686`
- **Jaeger Collector**: `jaeger-otel-collector:4317`
- **OTEL Collector**: `otel-collector:4317`
- **Elasticsearch**: `jaeger-otel-elasticsearch:9200`

## 🧪 Testing

### Send Test Traces

```bash
# Direct to Jaeger (bypass OTEL processing)
otel-cli span --endpoint http://localhost:4318 \
  --service test-direct --name direct-span

# Via OTEL Collector (with processing)
otel-cli span --endpoint http://localhost:4321 \
  --service test-otel --name processed-span

# Using gRPC
otel-cli span --endpoint http://localhost:4320 \
  --protocol grpc --service test-grpc --name grpc-span
```

### Verify Traces

```bash
# Check Jaeger services
curl -s http://localhost:16686/jaeger/api/services | jq .

# Search for traces
curl -s "http://localhost:16686/jaeger/api/traces?service=test-direct" | jq .
```

## 📈 Monitoring & Debugging

### OTEL Collector Monitoring

- **Z-pages**: Access cluster and port-forward `kubectl port-forward svc/otel-collector 55679:55679`
- **Prometheus**: http://localhost:8889/metrics
- **Health**: http://localhost:13133

### Jaeger Monitoring

- **UI**: Built-in service dependency graphs
- **Health**: Check collector health via `kubectl get pods`
- **Logs**: `kubectl logs -l app=jaeger`

### Troubleshooting Commands

```bash
# Check all Jaeger resources
kubectl get jaeger,pods,svc -l app=jaeger

# View OTEL Collector logs
kubectl logs -l app=otel-collector -f

# Check Jaeger Operator logs
kubectl logs -n observability deployment/jaeger-operator -f

# Describe failing pods
kubectl describe pod <pod-name>

# Check resource usage
kubectl top nodes
kubectl top pods
```

## 🧹 Cleanup

```bash
# Delete Jaeger instances
kubectl delete -f k8s-manifests/

# Delete Jaeger Operator
kubectl delete -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.60.0/jaeger-operator.yaml

# Delete Kind cluster
./delete-kind-cluster.sh
```

## 🔧 Customization

### Scaling Components

```bash
# Scale OTEL Collector
kubectl scale deployment otel-collector --replicas=3

# Scale Jaeger Collector (edit jaeger-instance.yaml)
# collector.replicas: 3
```

### Resource Adjustments

- Edit `k8s-manifests/otel-collector.yaml` for OTEL Collector resources
- Edit `k8s-manifests/jaeger-instance.yaml` for Jaeger component resources
- Modify `kind-config.yaml` for cluster-level resources

### Adding Authentication

- Configure OTEL Collector with auth extensions
- Add ingress controllers with authentication
- Implement RBAC policies

## 🚨 Production Considerations

This setup is optimized for development and testing. For production:

1. **Multi-AZ Deployment**: Use real Kubernetes cluster across availability zones
2. **External Elasticsearch**: Use managed Elasticsearch service
3. **Persistent Volumes**: Configure proper storage classes
4. **Security**: Implement authentication, TLS, network policies
5. **Monitoring**: Add Prometheus/Grafana stack
6. **Backup**: Configure Elasticsearch snapshots
7. **Resource Limits**: Tune based on expected load
8. **High Availability**: Increase replica counts
9. **Load Balancing**: Use ingress controllers
10. **Secret Management**: Use sealed secrets or external secret operators
