apiVersion: networking.linode.com/v1alpha1
kind: LinodeFirewall
metadata:
  name: ${WORKLOAD_NAME}
  namespace: ${WORKLOAD_NS}
spec:
  inbound:
    - label: "allow-http"
      action: "ACCEPT"
      description: "HTTP access for ${WORKLOAD_NAME}"
      protocol: "TCP"
      ports: "80"
      addresses:
        ipv4:
          - "0.0.0.0/0"
    - label: "allow-https"
      action: "ACCEPT"
      description: "HTTPS access for ${WORKLOAD_NAME}"
      protocol: "TCP"
      ports: "443"
      addresses:
        ipv4:
          - "0.0.0.0/0"
${EXTRA_PORTS_FW}