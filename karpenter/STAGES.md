https://github.com/linode/karpenter-provider-linode

# Skynet Deployment - Remaining Stages

### Steps
```bash
# 1. Install Traefik
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --values traefik-values.yaml \
  --wait

# 2. Create Let's Encrypt Issuer
kubectl apply -f traefik-http-issuer.yaml

# 3. Deploy test HTTPS service
kubectl apply -f test-https-deployment.yaml

# 4. Configure Linode Firewall (via Linode Cloud Manager or CLI)
# Allow HTTP (80), HTTPS (443) traffic to LKE nodes
```

---

## Stage N: Karpenter + Skynet

### Objectives
- GPU NodePool configuration with Karpenter
- Storage (PVC) for AI models mounted from Linode Block Storage
- Redis deployment for Skynet caching
- Skynet deployment with configurable modules
- Dynamic configuration via .env

### Files to Create
- `templates/linode-nodeclass.yaml.tpl`
- `templates/nodepool-gpu.yaml.tpl`
- `templates/storage.yaml.tpl`
- `templates/redis.yaml.tpl`
- `templates/deployment.yaml.tpl`
- `deploy-skynet.sh`
- `destroy-skynet.sh`

### GPU Selection Guide

| Configuration | SKYNET_GPU_INSTANCE_TYPE | SKYNET_GPU_LABELS | Notes |
|--------------|-------------------------|-------------------|-------|
| Cheapest GPU | (empty) | rtx4000a1 | RTX 4000 Ada, ~$150/mo |
| More VRAM | (empty) | rtx6000 | Older, ~$200/mo |
| Specific Type | gpu-8gb | (empty) | Fixed Linode type |
| Any GPU | (empty) | (empty) | Let Karpenter decide |

### Environment Variables

```bash
# GPU Configuration
SKYNET_GPU_INSTANCE_TYPE=     # empty, gpu-8gb, gpu-16gb
SKYNET_GPU_LABELS=rtx4000a1   # rtx4000a1, rtx6000, or empty
SKYNET_PREFER_SPOT=false      # true for cheaper spot instances

# Storage
SKYNET_MODEL_STORAGE_SIZE=50Gi   # Size for AI models
SKYNET_STORAGE_CLASS=linode-block-storage-retain

# Skynet Modules
SKYNET_ENABLED_MODULES=streaming_whisper,summaries,rag
SKYNET_WHISPER_MODEL=tiny.en
SKYNET_LLAMA_PATH=/models/Llama-3.1-8B-Instruct
```

### Deployment Flow
```bash
# 1. Configure
cp .env.sample .env
vim .env  # Add LINODE_TOKEN

# 2. Deploy
./deploy-skynet.sh

# 3. Verify
kubectl get pods -n $LINODE_CLI_NS -o wide
kubectl get nodes -l karpenter.k8s.linode/instance-gpu-name

# 4. Copy models to PVC (example)
kubectl exec -it deploy/skynet -- /bin/bash
# Then use wget/curl to download models to /models

# 5. Destroy
./destroy-skynet.sh
```

---

## Linode Firewall Configuration

When using LKE with Karpenter-provisioned nodes, you may need to configure firewall rules:

### Required Ports
| Port | Service | Purpose |
|------|---------|---------|
| 80 | HTTP | Let's Encrypt HTTP01 challenge |
| 443 | HTTPS | HTTPS traffic |
| 6443 | Kubernetes API | Cluster API access |

### Linode CLI Commands
```bash
# List existing firewalls
linode-cli firewalls list

# Create firewall for LKE
linode-cli firewalls create \
  --label skynet-karpenter \
  --region us-east

# Add rules (example)
linode-cli firewalls rules-update <firewall-id> \
  --inbound "{\"action\": \"ACCEPT\", \"protocol\": \"TCP\", \"ports\": \"80,443\", \"addresses\": {\"ipv4\": [\"0.0.0.0/0\"]}}" \
  --inbound "{\"action\": \"ACCEPT\", \"protocol\": \"TCP\", \"ports\": \"6443\", \"addresses\": {\"ipv4\": [\"your-ip/32\"]}}"
```

---

## Troubleshooting

### Karpenter Issues
```bash
# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -c controller -f

# Check NodePool events
kubectl describe nodepool

# Manually trigger node provisioning
kubectl scale deployment <test-deployment> --replicas=1
```

### Storage Issues
```bash
# Check PVC status
kubectl get pvc -n $NAMESPACE

# Check StorageClass
kubectl get storageclass

# Check CSI driver
kubectl get pods -n kube-system | grep csi-linode
```

### GPU Node Issues
```bash
# Check for GPU nodes
kubectl get nodes -l karpenter.k8s.linode/instance-gpu-name

# Check nvidia.com/gpu resource
kubectl describe nodes | grep -A5 "nvidia.com/gpu"
```
