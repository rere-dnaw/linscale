# Skynet Deployment on Kubernetes (GPU)

Deploys [Skynet](https://github.com/yourorg/skynet) AI server on Kubernetes with NVIDIA GPU support using Karpenter for node provisioning.

## Features

- **Streaming Whisper** - Real-time speech-to-text via WebSocket
- **Summaries** - LLM-powered text summarization with vLLM inference
- **Assistant** - RAG-based assistant with embeddings
- **GPU Support** - NVIDIA GPU passthrough for whisper and vLLM

## Prerequisites

1. **Kubernetes cluster** with Karpenter and Linode provider configured
2. **kubectl** configured to access the cluster
3. **Helm** for GPU Operator installation
4. **Docker** for building images (or use GitHub Actions)

## Quick Start

### 1. Configure

```bash
# Copy the example environment file
cp .env.example .env

# Edit with your values
vim .env
```

### 2. Build Image

**Option A: Using release script**
```bash
./scripts/release.sh latest
```

**Option B: Using GitHub Actions**
Push to master branch - automatically builds and pushes via `.github/workflows/build.yaml`

### 3. Deploy

```bash
./scripts/deploy.sh
```

### 4. Verify

```bash
# Check pod status
kubectl get pods -n workloads -l app=skynet -w

# Verify GPU allocation
kubectl describe pod -n workloads -l app=skynet | grep -A10 "Allocated resources"

# Test GPU access
kubectl exec -it -n workloads deployment/skynet -- nvidia-smi

# Check logs
kubectl logs -n workloads -l app=skynet --tail=100
```

## Configuration Reference

### Environment Variables

#### Core
| Variable | Description | Default |
|----------|-------------|---------|
| `WORKLOAD_NAME` | Kubernetes resource name | `skynet` |
| `WORKLOAD_NS` | Namespace | `workloads` |
| `WORKLOAD_IMAGE` | Docker image | (required) |
| `WORKLOAD_INSTANCE_TYPE` | Linode GPU instance | `g2-gpu-rtx4000a1-s` |

#### Resources
| Variable | Description | Default |
|----------|-------------|---------|
| `REPLICAS` | Pod replica count | `1` |
| `CPU_REQUEST` | CPU request | `2` |
| `MEMORY_REQUEST` | Memory request | `8Gi` |
| `CPU_LIMIT` | CPU limit | `4` |
| `MEMORY_LIMIT` | Memory limit | `16Gi` |

#### Authorization
| Variable | Description | Default |
|----------|-------------|---------|
| `BYPASS_AUTHORIZATION` | Skip JWT auth (dev only!) | `false` |
| `ASAP_PUB_KEYS_REPO_URL` | Public key repository URL | (required if auth enabled) |
| `ASAP_PUB_KEYS_FOLDER` | Path to keys folder | (required if auth enabled) |
| `ASAP_PUB_KEYS_AUDS` | Allowed JWT audiences | (required if auth enabled) |

#### Modules
| Variable | Description | Default |
|----------|-------------|---------|
| `ENABLED_MODULES` | Modules to load | `summaries:dispatcher,summaries:executor,streaming_whisper,assistant,customer_configs` |

#### Whisper (STT)
| Variable | Description | Default |
|----------|-------------|---------|
| `WHISPER_MODEL_PATH` | Model path (mounted volume) | `/models/streaming_whisper` |
| `WHISPER_COMPUTE_TYPE` | GPU quantization | `int8` |
| `WHISPER_GPU_INDICES` | GPU device index | `0` |
| `BEAM_SIZE` | Whisper beam size | `5` |

#### LLM (Summaries)
| Variable | Description | Default |
|----------|-------------|---------|
| `LLAMA_PATH` | vLLM model path | `/models/llama-3.1-8b-instruct` |
| `LLAMA_N_CTX` | Context window | `80000` |

#### Assistant (RAG)
| Variable | Description | Default |
|----------|-------------|---------|
| `EMBEDDINGS_MODEL_PATH` | Embeddings model | `BAAI/bge-m3` |
| `VECTOR_STORE_PATH` | Vector DB path | `/data/vector_store` |

#### Redis (Sidecar)
| Variable | Description | Default |
|----------|-------------|---------|
| `REDIS_HOST` | Redis hostname | `localhost` (sidecar) |
| `REDIS_PORT` | Redis port | `6379` |

## Model Preparation

### Option A: Download Models to PVC

After PVC is created, exec into the pod and download models:

```bash
# Get pod name
kubectl get pods -n workloads -l app=skynet

# Exec into pod
kubectl exec -it -n workloads -c app deployment/skynet -- /bin/bash

# Download whisper model
mkdir -p /models/streaming_whisper
huggingface-cli login
huggingface-cli download openai/whisper-tiny.en --repo-type model --cache-dir /models/streaming_whisper

# Download LLM model (requires more space)
mkdir -p /models
# Use huggingface-cli or wget to download your model
```

### Option B: Pre-load Models

Mount a hostPath volume or use a pre-populated PVC:

```yaml
# In deployment, replace the PVC with hostPath for development
volumes:
  - name: models
    hostPath:
      path: /path/to/models
```

## Authorization Setup (Production)

Skynet uses JWT authorization. To enable:

1. Generate RSA keypair:
   ```bash
   ssh-keygen -m PKCS8 -b 2048 -t rsa -f keys/private.key
   ```

2. Compute key ID (kid):
   ```bash
   echo -n "my-awesome-service" | shasum -a 256
   # cf83fb2ffe64d959f93c3ade60a1c45421f016be3dcbbeda9ea7f1b78afdb698
   ```

3. Upload public key:
   ```bash
   cp keys/private.key.pub cf83fb2ffe64d959f93c3ade60a1c45421f016be3dcbbeda9ea7f1b78afdb698.pem
   # Upload to your web server at ASAP_PUB_KEYS_REPO_URL
   ```

4. Set environment:
   ```bash
   BYPASS_AUTHORIZATION=false
   ASAP_PUB_KEYS_REPO_URL=https://keys.example.com
   ASAP_PUB_KEYS_FOLDER=/pub-keys
   ASAP_PUB_KEYS_AUDS=skynet-api
   ```

## GPU Operator

The GPU Operator is installed automatically by `deploy.sh` if not present. It manages:
- NVIDIA driver containers
- NVIDIA Device Plugin (advertises `nvidia.com/gpu`)
- Container Toolkit
- Node Feature Discovery

Manual installation:
```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
helm install --wait --generate-name -n gpu-operator --create-namespace nvidia/gpu-operator --version=v25.3
```

## Troubleshooting

### Pod not scheduling
```bash
# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50

# Check if nodes have GPU capacity
kubectl get nodes -o json | jq '.items[].status.capacity'
```

### GPU not allocated
```bash
# Verify device plugin is running
kubectl get pods -n gpu-operator

# Check nvidia-smi in pod
kubectl exec -it -n workloads deployment/skynet -c app -- nvidia-smi
```

### Model loading issues
```bash
# Check logs for model errors
kubectl logs -n workloads -l app=skynet --tail=100 | grep -i "model\|error"

# Verify models volume is mounted
kubectl describe pod -n workloads -l app=skynet | grep -A5 "Volumes"
```

## Cleanup

```bash
# Destroy workload keeping PVCs
./scripts/destroy.sh

# Destroy workload AND PVCs
./scripts/destroy.sh --destroy-pvc
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Node (g2-gpu-rtx4000a1-s)                          │   │
│  │                                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────────────┐   │   │
│  │  │ skynet pod      │  │ KarpenterNodeClass      │   │   │
│  │  │                 │  │ NodePool                │   │   │
│  │  │ ┌─────────────┐ │  │                         │   │   │
│  │  │ │ redis       │ │  │ taint: workload=skynet  │   │   │
│  │  │ │ (sidecar)   │ │  │                         │   │   │
│  │  │ └─────────────┘ │  └─────────────────────────┘   │   │
│  │  │ ┌─────────────┐ │                                │   │
│  │  │ │ skynet      │ │  ┌─────────────────────────┐   │   │
│  │  │ │ (main)      │ │  │ PVC: models             │   │   │
│  │  │ │ nvidia.com/ │ │  │ PVC: redis-data         │   │   │
│  │  │ │ gpu: 1      │ │  └─────────────────────────┘   │   │
│  │  │ └─────────────┘ │                                │   │
│  │  └─────────────────┘                                │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐    │
│  │ Traefik     │  │ cert-manager│  │ Karpenter       │    │
│  │ Ingress     │  │             │  │ Controller       │    │
│  └─────────────┘  └─────────────┘  └─────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 8000 | HTTP | Main API |
| 8001 | HTTP | Prometheus metrics |
| 8003 | HTTP | OpenAI-compatible API (vLLM) |
