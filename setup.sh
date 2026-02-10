#!/bin/bash
set -e

echo "=== Antrea Packet Capture Setup ==="

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed."; exit 1; }
command -v kind >/dev/null 2>&1 || { echo "Kind is required but not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "Helm is required but not installed."; exit 1; }

echo "✓ All prerequisites found"

# Delete existing cluster if any
echo ""
echo "=== Cleaning up existing cluster ==="
kind delete cluster --name antrea-test 2>/dev/null || true

# Create Kind cluster (single node for reliability)
echo ""
echo "=== Creating Kind Cluster (single node) ==="
cat <<EOF | kind create cluster --name antrea-test --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: 10.244.0.0/16
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /dev/null
    containerPath: /dev/null
EOF

echo "✓ Kind cluster created"

# Install Antrea
echo ""
echo "=== Installing Antrea ==="
helm repo add antrea https://charts.antrea.io
helm repo update
helm install antrea antrea/antrea --namespace kube-system --wait

echo "✓ Antrea installed"

# Build and load image
echo ""
echo "=== Building Controller Image ==="
docker build -t packet-capture:latest .

echo "✓ Image built"

echo ""
echo "=== Loading Image into Kind ==="
kind load docker-image packet-capture:latest --name antrea-test

echo "✓ Image loaded"

# Deploy controller
echo ""
echo "=== Deploying Packet Capture Controller ==="
kubectl apply -f manifests/daemonset.yaml
kubectl rollout status daemonset/packet-capture -n kube-system --timeout=120s

echo "✓ Controller deployed"

echo ""
echo "=== Setup Complete ==="
echo "Run './test.sh' to test the packet capture functionality"
