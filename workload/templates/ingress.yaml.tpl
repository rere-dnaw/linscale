apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: ${WORKLOAD_NAME}
  namespace: ${WORKLOAD_NS}
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`${WEB_HOST}`)
      kind: Rule
      services:
        - name: ${WORKLOAD_NAME}
          port: 80
      middlewares:
        - name: ${WORKLOAD_NAME}-headers
          namespace: ${WORKLOAD_NS}
  tls:
    secretName: wildcard-tls
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: ${WORKLOAD_NAME}-headers
  namespace: ${WORKLOAD_NS}
spec:
  headers:
    customRequestHeaders:
      X-Forwarded-Proto: "https"