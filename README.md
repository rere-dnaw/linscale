# k8scale - Kubernetes Cluster Setup

Orchestration scripts for deploying a full Kubernetes stack on Linode LKE.

## Stages

| Stage | Description |
|-------|-------------|
| `linode-cli` | Linode CLI pod with credentials for kubectl exec |
| `linode-firewall` | Linode Cloud Firewall controller (Helm) |
| `cert-manager` | cert-manager with Linode DNS-01 webhook |
| `traefik` | Traefik ingress controller with HTTPS |
| `karpenter` | Karpenter GPU node provisioning |

## References
https://github.com/linode/cloud-firewall-controller
https://github.com/linode/cert-manager-webhook-linode
https://github.com/linode/karpenter-provider-linode
https://github.com/linode/linode-cli


## Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) configured for your LKE cluster
- [Helm 3](https://helm.sh/docs/intro/install/)
- [linode-cli](https://www.linode.com/products/cli/) (optional, for manual operations)
- [jq](https://stedolan.github.io/jq/) (for instance selector script)
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

## Create Linode Personal Access Token
1. Log in to [Linode Cloud Manager](https://cloud.linode.com)
2. Go to your **Profile** (top right) → **API Tokens** → **Create A Personal Access Token**
3. Set the following:
   - **Label**: `cert-manager-dns` (or similar)
   - **Expiry**: Choose a reasonable period (e.g., 12 months)
   - **Scopes**: Set all to `No Access`, then set **Domains** to `Read/Write`
4. Click **Create Token**
5. **Copy the token immediately** - it will not be shown again

## Domain SOA TTL
Before proceeding, ensure your domain's SOA record TTL is set to 30 seconds:

1. In Linode Cloud Manager, go to **Domains**
2. Click on your domain (`portal7.eu`)
3. Find the **SOA Record**, click the three dots → **Edit**
4. Change TTL to **30 seconds**
5. Click **Save**

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
kubectl exec -it linode-cli -- linode-cli linodes list

# Alternative: Run single command without sleep
kubectl run linode-cli-test --rm -it --image=linode/cli:latest --restart=Never -- \
  linodes list
```

### Instance Selector (for Karpenter GPU nodepools)

Interactive script to select Linode instance types, grouped by class and GPU label:

```bash
# Interactive mode - select from grouped menu
LINODE_TYPE=$(./linode-cli/select-instance.sh)

# Direct mode - specify instance ID, falls back to alternatives if unavailable
LINODE_TYPE=$(./linode-cli/select-instance.sh g2-gpu-rtx4000-ada-1xmedium)
```

**Features:**
- Groups instances by class (standard, gpu, highmem, dedicated, premium) and GPU label (RTX4000 Ada, RTX6000, etc.)
- Direct selection validates instance availability
- If requested instance unavailable, shows numbered alternatives within same class+GPU group

**Requires:** `jq` installed locally (e.g. `sudo apt install jq` or `brew install jq`)

## Git hooks
If problem try 
```bash
rm -rf .git/hooks/*
poetry run pre-commit autoupdate
poetry run pre-commit install
```


# TODO
- [ ] automate domain creation
- [ ] cert with *.domain
- [ ] PVC is destroyeed but volume I keept. Fix it.