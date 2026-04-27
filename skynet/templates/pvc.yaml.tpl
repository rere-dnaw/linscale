apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${WORKLOAD_NAME}-models
  namespace: ${WORKLOAD_NS}
spec:
  accessModes:
    - ${PVC_ACCESS_MODE}
  resources:
    requests:
      storage: ${PVC_SIZE}
  storageClassName: ${PVC_STORAGE_CLASS}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${WORKLOAD_NAME}-redis-data
  namespace: ${WORKLOAD_NS}
spec:
  accessModes:
    - ${PVC_ACCESS_MODE}
  resources:
    requests:
      storage: 10Gi
  storageClassName: ${PVC_STORAGE_CLASS}
