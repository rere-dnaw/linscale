# k8scale - Kubernetes Cluster Setup

Orchestration scripts for deploying a full Kubernetes stack on Linode LKE.

## Stages

| Stage | Description |
|-------|-------------|
| `linode-cli` | Linode CLI pod with credentials for kubectl exec |
| `linode-firewall` | Linode Cloud Firewall controller (Helm) |
| `cert-manager` | cert-manager with Linode DNS-01 webhook |
| `traefik` | Traefik ingress controller with HTTPS |
| `karpenter` | Karpenter GPU node provisioning (**NOT IMPLEMENTED - placeholder**) |

## References
https://github.com/linode/cloud-firewall-controller


## Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) configured for your LKE cluster
- [Helm 3](https://helm.sh/docs/intro/install/)
- [linode-cli](https://www.linode.com/products/cli/) (optional, for manual operations)
- LKE cluster running

## Quick Start

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Edit .env with your Linode tokens
vim .env

# 3. Deploy all stages
./main.sh deploy all

# 4. Check status
./main.sh status
```

## Token Setup

Get tokens from: https://cloud.linode.com/profile/tokens

| Token | Purpose | Required Scopes |
|-------|---------|-----------------|
| `LINODE_CLI_TOKEN` | Linode CLI pod (kubectl exec) | Read/Write for Linodes |
| `CERT_MANAGER_TOKEN` | DNS-01 challenge (Linode webhook) | Read/Write for Domains |
| `KARPENTER_TOKEN` | Karpenter (future) | Read/Write |

## Usage

```bash
# Deploy all stages
./main.sh deploy all

# Deploy specific stage
./main.sh deploy cert-manager

# Destroy all stages (reverse order)
./main.sh destroy all

# Destroy specific stage
./main.sh destroy traefik

# Show status
./main.sh status

# Help
./main.sh help
```

## Deployment Order

```
linode-cli → linode-firewall → cert-manager → traefik
```

## Destroy Order

```
traefik → cert-manager → linode-firewall → linode-cli
```

## Per-Stage Commands

You can also run deploy/destroy scripts directly:

```bash
# Deploy stages individually
cd linode-cli && ./deploy.sh
cd ../linode-firewall && ./deploy.sh
cd ../cert-manager && ./deploy.sh
cd ../traefik && ./deploy.sh

# Destroy stages individually
cd traefik && ./destroy.sh
cd ../cert-manager && ./destroy.sh
cd ../linode-firewall && ./destroy.sh
cd ../linode-cli && ./destroy.sh
```

## Verification

```bash
# Check all pods
kubectl get pods -A

# Check cert-manager
kubectl get pods -n cert-manager
kubectl get clusterissuer

# Check Traefik
kubectl get pods -n traefik
kubectl get gateways -n traefik

# Check certificates
kubectl get certificates --all-namespaces

# Test Linode CLI
kubectl exec -it -n default linode-cli -- linode-cli linodes list

# Traefik dashboard
# https://traefik.portal7.eu
# Credentials: from .env (TRAEFIK_USER / TRAEFIK_PASSWORD)
```

## Notes

- `.env` is gitignored (local only)
- `.env.example` is versioned for reference
- Karpenter stage is a placeholder with a warning - not functional yet
- cert-manager requires your domain's SOA TTL to be set to 30 seconds

## Troubleshooting

```bash
# Check cert-manager ClusterIssuer
kubectl describe clusterissuer letsencrypt-prod

# Check traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f

# Check linode-cli
kubectl logs -n default linode-cli

# Delete everything and start fresh
./main.sh destroy all
```

### Linode-cli

```bash
# List all Linodes
kubectl exec -it linode-cli -- linodes list

# Alternative: Run single command without sleep
kubectl run linode-cli-test --rm -it --image=linode/cli:latest --restart=Never -- \
  linodes list
```