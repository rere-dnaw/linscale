apiVersion: v1
kind: Service
metadata:
  name: ${WORKLOAD_NAME}
  namespace: ${WORKLOAD_NS}
spec:
  type: NodePort
  selector:
    app: ${WORKLOAD_NAME}
  ports:
    - name: http
      port: 80
      targetPort: ${WEB_PORT}
      protocol: TCP
    - name: metrics
      port: 8001
      targetPort: 8001
      protocol: TCP
    - name: openai
      port: 8003
      targetPort: 8003
      protocol: TCP
${EXTRA_PORTS_SVC}
