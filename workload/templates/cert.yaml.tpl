apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${WORKLOAD_NAME}
  namespace: ${WORKLOAD_NS}
spec:
  secretName: ${WORKLOAD_NAME}-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - ${WEB_HOST}