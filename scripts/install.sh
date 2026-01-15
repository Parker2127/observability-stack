#!/bin/bash
# Install observability stack on Kubernetes

set -e

NAMESPACE="monitoring"

echo "🚀 Installing Observability Stack on Kubernetes..."

# Create namespace
echo "📦 Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install Prometheus using Helm
echo "📊 Installing Prometheus..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  --set prometheus.prometheusSpec.retention=90d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi

# Install Loki
echo "📝 Installing Loki..."
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace $NAMESPACE \
  --set grafana.enabled=false \
  --set promtail.enabled=true

# Install Jaeger
echo "🔍 Installing Jaeger..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: jaeger
  namespace: $NAMESPACE
spec:
  ports:
  - port: 16686
    name: query
  - port: 14268
    name: collector
  selector:
    app: jaeger
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:latest
        ports:
        - containerPort: 16686
        - containerPort: 14268
        env:
        - name: COLLECTOR_OTLP_ENABLED
          value: "true"
EOF

echo "⏳ Waiting for deployments..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/prometheus-kube-prometheus-operator -n $NAMESPACE

echo "✅ Observability Stack installed successfully!"
echo ""
echo "Access dashboards:"
echo "  Grafana:    kubectl port-forward svc/prometheus-grafana 3000:80 -n $NAMESPACE"
echo "  Prometheus: kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n $NAMESPACE"
echo "  Jaeger:     kubectl port-forward svc/jaeger 16686:16686 -n $NAMESPACE"
echo ""
echo "Grafana credentials:"
echo "  Username: admin"
echo "  Password: $(kubectl get secret prometheus-grafana -n $NAMESPACE -o jsonpath="{.data.admin-password}" | base64 --decode)"
