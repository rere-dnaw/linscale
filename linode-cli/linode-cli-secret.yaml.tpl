apiVersion: v1
kind: Secret
metadata:
  name: linode-credentials
  namespace: ${LINODE_CLI_NS}
type: Opaque
stringData:
  token: "${LINODE_TOKEN}"
