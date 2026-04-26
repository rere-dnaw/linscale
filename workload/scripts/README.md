# Workload Scripts

Scripts for deploying workloads with Karpenter nodepools.

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Deploy a workload with TLS, PVC, firewall, and Karpenter nodepool |
| `destroy.sh` | Tear down a workload |

## Usage

```bash
# Deploy workload (interactive instance selection)
./deploy.sh

# Deploy using last run config
./deploy.sh --last-run

# Destroy workload
./destroy.sh
```

## select-instance.sh

Interactive Linode instance selector for GPU nodepools. Used by `deploy.sh` when `WORKLOAD_INSTANCE_TYPE` is not set. Can also be run standalone:

```bash
LINODE_CLI_NS=kube-system LINODE_REGION=de-fra-2 ./select-instance.sh [instance-type-id]
```

Requires: `jq`

## TODO:

- [ ] Investigate idle detection. e.g. if no user access service for last 1h destroy deployment with pool