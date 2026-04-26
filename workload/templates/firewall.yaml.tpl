apiVersion: networking.linode.com/alpha1v1
kind: CloudFirewall
metadata:
  name: ${WORKLOAD_NAME}
spec:
  defaultRules: false
  ruleset:
    inbound:
    - label: "allow-http"
      action: ACCEPT
      description: "HTTP access for ${WORKLOAD_NAME}"
      protocol: TCP
      ports: "80"
      addresses:
        ipv4:
        - 0.0.0.0/0
    - label: "allow-https"
      action: ACCEPT
      description: "HTTPS access for ${WORKLOAD_NAME}"
      protocol: TCP
      ports: "443"
      addresses:
        ipv4:
        - 0.0.0.0/0
${EXTRA_PORTS_FW}
    inbound_policy: DROP
    outbound: []
    outbound_policy: ACCEPT