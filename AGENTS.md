# k8scale - Kubernetes Cluster Setup

Orchestrates a full Kubernetes stack on Linode LKE via stage scripts.

## Entry point

```bash
./main.sh deploy|destroy|status [stage|all]
```

## Stage order

Deploy: `linode-cli → linode-firewall → cert-manager → traefik`
Destroy: reverse order (traefik → cert-manager → linode-firewall → linode-cli)
Karpenter is separate (not in main deploy loop, has its own deploy/destroy).

## Architecture

| Directory | Purpose |
|-----------|---------|
| `main.sh` | Orchestrator - deploys/destroys stages in order |
| `linode-cli/` | CLI pod with Linode credentials for kubectl exec |
| `linode-firewall/` | Linode Cloud Firewall controller (Helm) |
| `cert-manager/` | cert-manager with Linode DNS-01 webhook |
| `traefik/` | Traefik ingress controller with HTTPS |
| `karpenter/` | Karpenter GPU node provisioning (standalone, not auto-deployed) |
| `skynet/` | AI workload - deploy via `skynet/scripts/deploy.sh` |
| `workload/` | Generic workload templates - deploy via `workload/scripts/deploy.sh` |

## Key commands

```bash
# Deploy infra stages (in order)
./main.sh deploy all
./main.sh deploy cert-manager  # single stage

# Deploy AI workload (requires GPU operator, linode-cli, firewall controller running)
cd skynet && ./scripts/deploy.sh

# Deploy generic workload (same prerequisites)
cd workload && ./scripts/deploy.sh
cd workload && ./scripts/deploy.sh --last-run  # reuse last config

# Destroy
./main.sh destroy all
```

## Prerequisites for workload deploy (skynet / workload)

1. `linode-cli` pod must be running (`kubectl get pod linode-cli`)
2. `cloud-firewall-controller` must be running in `kube-system`
3. GPU Operator must be installed (auto-installed by `deploy.sh` if missing)
4. Domain SOA TTL must be 30 seconds (for cert-manager DNS-01)

Workload deploy scripts check these and exit 1 if missing.

## Environment files

- `.env` at root - Linode tokens, Traefik credentials, domain config (gitignored)
- `.env.example` - template with all required variables documented
- `workload/` and `skynet/` have their own `.env` files for workload-specific config

## Image build for skynet

Push to master branch → `.github/workflows/build.yaml` builds and pushes to `ghcr.io`.
Or run locally: `cd skynet && docker build -t ...`

## cert-manager setup

Requires `CERT_MANAGER_TOKEN` (Linode token with Domains read/write).
Domain SOA TTL must be 30 seconds before deploy.

## Pre-commit

Only gitleaks is configured. Run: `pre-commit run --all-files`

## Karpenter

Not part of `main.sh` deploy loop. Deploy separately with env vars:
```bash
KARPENTER_TOKEN=... KARPENTER_CLUSTER_NAME=... ./karpenter/deploy.sh
```
Requires `KARPENTER_PROVIDER_DIR` pointing to the Linode karpenter-provider charts.

## select-instance.sh

Interactive Linode instance selector for GPU nodepools. Used by deploy scripts when `WORKLOAD_INSTANCE_TYPE` not set. Requires `jq`.