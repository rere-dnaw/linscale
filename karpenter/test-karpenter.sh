#!/bin/bash
set -e

NAMESPACE="${KARPENTER_NS:-default}"
TIMEOUT=600

ORIGINAL_NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

echo "=== Applying NodeClass + NodePool + Deployment (namespace: $NAMESPACE) ==="
kubectl apply -f - <<EOF
apiVersion: karpenter.k8s.linode/v1alpha1
kind: LinodeNodeClass
metadata:
  name: $NAMESPACE
spec:
  image: "linode/ubuntu22.04"
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: $NAMESPACE
spec:
  template:
    metadata:
      labels:
        k8scale-test: enabled
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
      nodeClassRef:
        group: karpenter.k8s.linode
        kind: LinodeNodeClass
        name: $NAMESPACE
      expireAfter: 1h
  limits:
    cpu: 1000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: $NAMESPACE
spec:
  replicas: 0
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      terminationGracePeriodSeconds: 0
      nodeSelector:
        k8scale-test: "enabled"
      securityContext:
        runAsUser: 1000
        runAsGroup: 3000
        fsGroup: 2000
      containers:
      - name: inflate
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        resources:
          requests:
            cpu: 1
        securityContext:
          allowPrivilegeEscalation: false
EOF

echo "=== Scaling inflate to 5 replicas to trigger Karpenter ==="
kubectl scale deployment inflate -n "$NAMESPACE" --replicas=5

echo "=== Waiting for pods to be ready (timeout: ${TIMEOUT}s) ==="
kubectl wait --for=condition=Ready pod -l app=inflate -n "$NAMESPACE" --timeout=${TIMEOUT}s

echo "=== Verifying pods are running on NEW nodes ==="
NEW_NODE=""
for i in $(seq 1 30); do
    POD_NODE=$(kubectl get pods -l app=inflate -n "$NAMESPACE" -o jsonpath='{.items[0].spec.nodeName}')
    if [ -n "$POD_NODE" ]; then
        if echo "$ORIGINAL_NODES" | grep -qv "$POD_NODE"; then
            NEW_NODE="$POD_NODE"
            break
        fi
        echo "Pod still on original node, waiting..."
    fi
    sleep 2
done

if [ -z "$NEW_NODE" ]; then
    echo "ERROR: Pods are not running on a new node!"
    exit 1
fi

echo "Pods running on new node: $NEW_NODE"
kubectl get pods -l app=inflate -n "$NAMESPACE" -o wide
kubectl get nodes

echo "=== Scaling down and cleaning up ==="
kubectl scale deployment inflate -n "$NAMESPACE" --replicas=0
kubectl delete -f - <<EOF
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: $NAMESPACE
---
apiVersion: karpenter.k8s.linode/v1alpha1
kind: LinodeNodeClass
metadata:
  name: $NAMESPACE
EOF

echo "=== Waiting for node $NEW_NODE to disappear (timeout: ${TIMEOUT}s) ==="
NODE_GONE=0
for i in $(seq 1 $((TIMEOUT / 5))); do
    if kubectl get nodes | grep -q "$NEW_NODE"; then
        sleep 5
    else
        NODE_GONE=1
        break
    fi
done

if [ "$NODE_GONE" -eq 0 ]; then
    echo "ERROR: Node $NEW_NODE still present after ${TIMEOUT}s timeout"
    exit 1
fi

echo "=== Node $NEW_NODE is gone ==="
kubectl get nodes

echo "=== Test complete ==="