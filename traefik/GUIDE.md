# Traefik Ingress Controller — Quick Guide

## Prerequisites
- cert-manager with `letsencrypt-prod` ClusterIssuer already deployed
- Linode DNS token secret (`linode-token-secret`) created
- Domain `portal7.eu` configured in Linode DNS

## Deploy
```bash
cd skynet-karpenter/traefik
./deploy.sh
```

## DNS
Add an A record for `traefik.portal7.eu` pointing to your cluster's external IP:

## Dashboard Access
The deploy script automatically creates the auth secret with `admin:admin` credentials.

## Updating Dashboard Password

To change the dashboard password, regenerate the auth hash and update the secret:

```bash
# Set your new credentials
USER=<NEW_USER>
PASSWORD=<NEW_PASSWORD>

# Generate new hash via temporary pod
kubectl run htpasswd-generator --image=httpd:alpine --rm -it --restart=Never -- \
  /bin/sh -c "printf '$PASSWORD\n$PASSWORD\n' | htpasswd -nBi $USER"

# Get the hash from output, then update secret:
kubectl create secret generic traefik-dashboard-auth -n traefik \
  --from-literal=auth="$USER:<hash>" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod htpasswd-generator 2>/dev/null || true
```

## Dashboard Ingress (post-deploy)
```bash
kubectl apply -f ingress-route.yaml
kubectl get ingressroute -n traefik
```

## Verify
```bash
# Check all resources
kubectl get all -n traefik

# Check ingressclass
kubectl get ingressclass

# Check TLS certificates
kubectl get certificate

# Test dashboard
curl -v https://traefik.portal7.eu/dashboard/
```

## Useful Commands
```bash
# Watch traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f

# Restart traefik
kubectl rollout restart deployment/traefik -n traefik

# Check cert-manager certificates
kubectl describe certificate -n traefik

# External IP (your nodes):
kubectl get nodes -o wide
```

## Destroy
```bash
./destroy.sh
```
