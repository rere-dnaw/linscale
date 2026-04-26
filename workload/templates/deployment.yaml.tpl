apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${WORKLOAD_NAME}
  namespace: ${WORKLOAD_NS}
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: ${WORKLOAD_NAME}
  template:
    metadata:
      labels:
        app: ${WORKLOAD_NAME}
    spec:
      terminationGracePeriodSeconds: 30
      nodeSelector:
        workload: ${WORKLOAD_NAME}
      tolerations:
        - key: workload
          value: ${WORKLOAD_NAME}
          operator: Equal
          effect: NoSchedule
      containers:
        - name: app
          image: ${WORKLOAD_IMAGE}
          ports:
            - name: http
              containerPort: ${WEB_PORT}
              protocol: TCP
          resources:
            requests:
              cpu: ${CPU_REQUEST}
              memory: ${MEMORY_REQUEST}
            limits:
              cpu: ${CPU_LIMIT}
              memory: ${MEMORY_LIMIT}
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20