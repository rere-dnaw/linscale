# Linode Token Secret - Manual Setup Instructions

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

## Create the Secret
Run the following command, replacing `YOUR_LINODE_TOKEN` with the token you just created:

```bash
kubectl create secret generic linode-token-secret \
  -n cert-manager \
  --from-literal=token=YOUR_LINODE_TOKEN
```

## Verify the Secret

```bash
kubectl get secret linode-token-secret -n cert-manager
kubectl describe secret linode-token-secret -n cert-manager
```

## Update the Token

```bash
kubectl delete secret linode-token-secret -n cert-manager
kubectl create secret generic linode-token-secret \
  -n cert-manager \
  --from-literal=token=NEW_LINODE_TOKEN
```

## Verify ClusterIssuer
After the secret is created, check that cert-manager can use it:

```bash
kubectl describe clusterissuer letsencrypt-production
```

Look for `The ACME account was successfully registered` in the events.
