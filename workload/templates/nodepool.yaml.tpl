apiVersion: karpenter.k8s.linode/v1alpha1
kind: LinodeNodeClass
metadata:
  name: ${WORKLOAD_NAME}
  namespace: ${WORKLOAD_NS}
spec:
  image: "linode/ubuntu22.04"
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ${WORKLOAD_NAME}
  namespace: ${WORKLOAD_NS}
spec:
  template:
    metadata:
      labels:
        workload: ${WORKLOAD_NAME}
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["${WORKLOAD_INSTANCE_TYPE}"]
      nodeClassRef:
        group: karpenter.k8s.linode
        kind: LinodeNodeClass
        name: ${WORKLOAD_NAME}
      taints:
        - key: workload
          value: ${WORKLOAD_NAME}
          effect: NoSchedule
      expireAfter: Never
  limits:
    cpu: "${CPU_LIMIT_CORE}"
  weight: 100