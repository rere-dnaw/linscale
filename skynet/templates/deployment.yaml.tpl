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
      terminationGracePeriodSeconds: 60
      nodeSelector:
        workload: ${WORKLOAD_NAME}
      tolerations:
        - key: workload
          value: ${WORKLOAD_NAME}
          operator: Equal
          effect: NoSchedule
      containers:
        - name: redis
          image: redis:alpine
          ports:
            - containerPort: 6379
              protocol: TCP
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
          volumeMounts:
            - name: redis-data
              mountPath: /data
        - name: app
          image: ${WORKLOAD_IMAGE}
          ports:
            - name: http
              containerPort: ${WEB_PORT}
              protocol: TCP
            - name: metrics
              containerPort: 8001
              protocol: TCP
            - name: openai
              containerPort: 8003
              protocol: TCP
          env:
            - name: SKYNET_PORT
              value: "${WEB_PORT}"
            - name: SKYNET_LISTEN_IP
              value: "0.0.0.0"
            - name: LOG_LEVEL
              value: "DEBUG"
            - name: ENABLED_MODULES
              value: "${ENABLED_MODULES}"
            - name: BYPASS_AUTHORIZATION
              value: "${BYPASS_AUTHORIZATION}"
            - name: ASAP_PUB_KEYS_REPO_URL
              value: "${ASAP_PUB_KEYS_REPO_URL}"
            - name: ASAP_PUB_KEYS_FOLDER
              value: "${ASAP_PUB_KEYS_FOLDER}"
            - name: ASAP_PUB_KEYS_AUDS
              value: "${ASAP_PUB_KEYS_AUDS}"
            - name: REDIS_HOST
              value: "${REDIS_HOST}"
            - name: REDIS_PORT
              value: "${REDIS_PORT}"
            - name: LLAMA_PATH
              value: "${LLAMA_PATH}"
            - name: LLAMA_N_CTX
              value: "${LLAMA_N_CTX}"
            - name: WHISPER_MODEL_PATH
              value: "${WHISPER_MODEL_PATH}"
            - name: WHISPER_COMPUTE_TYPE
              value: "${WHISPER_COMPUTE_TYPE}"
            - name: WHISPER_GPU_INDICES
              value: "${WHISPER_GPU_INDICES}"
            - name: BEAM_SIZE
              value: "${BEAM_SIZE}"
            - name: EMBEDDINGS_MODEL_PATH
              value: "${EMBEDDINGS_MODEL_PATH}"
            - name: VECTOR_STORE_PATH
              value: "/data/vector_store"
            - name: ENABLE_METRICS
              value: "true"
            - name: OUTLINES_CACHE_DIR
              value: "/app/vllm/outlines"
            - name: VLLM_CACHE_ROOT
              value: "/app/vllm/cache"
            - name: VLLM_CONFIG_ROOT
              value: "/app/vllm/config"
            - name: HF_HOME
              value: "/app/hf"
            - name: PYTHONUNBUFFERED
              value: "1"
            - name: PYTHONDONTWRITEBYTECODE
              value: "1"
            - name: PYTHONPATH
              value: "/app"
            - name: TMPDIR
              value: "/app/tmp"
          resources:
            requests:
              cpu: ${CPU_REQUEST}
              memory: ${MEMORY_REQUEST}
            limits:
              cpu: ${CPU_LIMIT}
              memory: ${MEMORY_LIMIT}
              nvidia.com/gpu: 1
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 10
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 60
            periodSeconds: 20
            failureThreshold: 5
          volumeMounts:
            - name: models
              mountPath: /models
            - name: app-data
              mountPath: /app
            - name: redis-data
              mountPath: /data
      volumes:
        - name: models
          persistentVolumeClaim:
            claimName: ${WORKLOAD_NAME}-models
        - name: app-data
          emptyDir: {}
        - name: redis-data
          persistentVolumeClaim:
            claimName: ${WORKLOAD_NAME}-redis-data
