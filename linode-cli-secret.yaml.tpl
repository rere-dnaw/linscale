apiVersion: v1
kind: Secret
metadata:
  name: linode-credentials
  namespace: ${SKYNET_NAMESPACE}
type: Opaque
stringData:
  token: "${LINODE_TOKEN}"
