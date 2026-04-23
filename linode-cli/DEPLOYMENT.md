# Linode CLI Deployment

## Required Token Permissions

The Linode Personal Access Token needs the following scopes for `linodes list`:

| Scope | Permission |
|-------|------------|
| `linodes:read` | Grants read-only access to list linodes |

Generate a token at: https://cloud.linode.com/profile/tokens

## Local Docker Test

Test the CLI locally before deploying to Kubernetes:

```bash
# Pull the image
docker pull linode/cli:latest

# Run with token from environment
LINODE_TOKEN="your-token-here" docker run --rm -it \
  -e LINODE_CLI_TOKEN \
  -v $HOME/.config/linode-cli:/home/cli/.config/linode-cli \
  linode/cli:latest linodes list
```

## Kubernetes Deployment

### 1. Create Secret

```bash
kubectl create secret generic linode-cli-config \
  --from-literal=LINODE_CLI_TOKEN="$LINODE_TOKEN"
```

### 2. Deployment Manifest

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: linode-cli
  namespace: default
spec:
  containers:
  - name: linode-cli
    image: linode/cli:latest
    command: ["sleep", "infinity"]
    env:
    - name: LINODE_CLI_TOKEN
      valueFrom:
        secretKeyRef:
          name: linode-cli-config
          key: LINODE_CLI_TOKEN
    volumeMounts:
    - name: linode-config
      mountPath: /home/cli/.config/linode-cli
  volumes:
  - name: linode-config
    emptyDir: {}
  restartPolicy: Never
```

Apply with:

```bash
kubectl apply -f deployment.yaml
```

### 3. Execute Commands in Pod

```bash
# List all Linodes
kubectl exec -it linode-cli -- linodes list

# Alternative: Run single command without sleep
kubectl run linode-cli-test --rm -it --image=linode/cli:latest --restart=Never -- \
  linodes list
```

## Quick One-Liner (No Deployment)

For a single command execution:

```bash
kubectl run linode-cli --rm -it --image=linode/cli:latest --restart=Never --overrides='
{"spec":{"containers":[{"name":"linode-cli","image":"linode/cli:latest","env":[{"name":"LINODE_CLI_TOKEN","valueFrom":{"secretKeyRef":{"name":"linode-cli-config","key":"LINODE_CLI_TOKEN"}}}]}]}}' -- linodes list
```