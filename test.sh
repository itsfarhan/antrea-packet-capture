#!/bin/bash
set -e

echo "=== Testing Packet Capture ==="

# Deploy test pod
echo ""
echo "=== Deploying Test Pod ==="
kubectl apply -f manifests/test-pod.yaml
kubectl wait --for=condition=Ready pod/test-pod --timeout=120s

echo "✓ Test Pod running"

# Get node and capture pod
NODE=$(kubectl get pod test-pod -o jsonpath='{.spec.nodeName}')
CAPTURE_POD=$(kubectl get pod -n kube-system -l app=packet-capture --field-selector spec.nodeName=$NODE -o jsonpath='{.items[0].metadata.name}')

echo "Test Pod on node: $NODE"
echo "Capture Pod: $CAPTURE_POD"

# Save pod describe
echo ""
echo "=== Saving Pod Description (before annotation) ==="
kubectl describe pod test-pod > outputs/pod-describe-before.txt
echo "✓ Saved to outputs/pod-describe-before.txt"

# Annotate pod
echo ""
echo "=== Starting Packet Capture ==="
kubectl annotate pod test-pod tcpdump.antrea.io="5"

echo "Waiting 15 seconds for capture to collect data..."
sleep 15

# Save pod describe with annotation
echo ""
echo "=== Saving Pod Description (with annotation) ==="
kubectl describe pod test-pod > outputs/pod-describe.txt
echo "✓ Saved to outputs/pod-describe.txt"

# Check capture files
echo ""
echo "=== Checking Capture Files ==="
kubectl exec -n kube-system $CAPTURE_POD -- sh -c "ls -lh /capture-* 2>/dev/null || echo 'No files yet'" | tee outputs/capture-files.txt

# Wait a bit more
echo "Waiting 10 more seconds..."
sleep 10

# Check again
kubectl exec -n kube-system $CAPTURE_POD -- sh -c "ls -lh /capture-*" | tee outputs/capture-files.txt

# Copy pcap file
echo ""
echo "=== Copying PCAP File ==="
PCAP_FILE=$(kubectl exec -n kube-system $CAPTURE_POD -- sh -c "ls /capture-test-pod.pcap* | head -1")
kubectl cp kube-system/$CAPTURE_POD:$PCAP_FILE outputs/capture.pcap

echo "✓ PCAP file copied to outputs/capture.pcap"

# Read pcap
echo ""
echo "=== Reading PCAP File ==="
tcpdump -r outputs/capture.pcap -n | head -100 > outputs/capture-output.txt
echo "✓ Saved to outputs/capture-output.txt"

# Get all pods
echo ""
echo "=== Saving Pod List ==="
kubectl get pods -A > outputs/pods.txt
echo "✓ Saved to outputs/pods.txt"

# Stop capture
echo ""
echo "=== Stopping Packet Capture ==="
kubectl annotate pod test-pod tcpdump.antrea.io-

echo "Waiting 5 seconds for cleanup..."
sleep 5

# Verify cleanup
echo ""
echo "=== Verifying Cleanup ==="
kubectl exec -n kube-system $CAPTURE_POD -- sh -c "ls /capture-* 2>/dev/null && echo 'ERROR: Files still exist!' || echo '✓ Files deleted successfully'"

echo ""
echo "=== Test Complete ==="
echo "All outputs saved to outputs/ directory"
