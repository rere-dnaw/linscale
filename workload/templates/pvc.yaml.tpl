apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${WORKLOAD_NAME}-data
  namespace: ${WORKLOAD_NS}
spec:
  accessModes:
    - ${PVC_ACCESS_MODE}
  resources:
    requests:
      storage: ${PVC_SIZE}
  storageClassName: ${PVC_STORAGE_CLASS}