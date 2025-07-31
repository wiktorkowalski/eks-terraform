# Karpenter Implementation Guide

## Overview

Karpenter is a flexible, high-performance Kubernetes cluster autoscaler that can quickly provision right-sized compute resources in response to changing application load. This guide covers implementing Karpenter to replace the current EKS managed node groups.

## Current State Analysis

Your current setup uses EKS managed node groups with:
- `main` node group: m6g.medium instances (SPOT)
- `spot` node group: m6g.large instances (SPOT)
- Static sizing with min/desired/max configurations

## Benefits of Karpenter Migration

1. **Cost Optimization**: Better instance selection and faster scaling
2. **Performance**: Sub-minute node provisioning vs 3-5 minutes with node groups
3. **Flexibility**: Wide range of instance types and availability zones
4. **Simplified Management**: No need to manage multiple node groups

## Implementation Steps

### 1. Update Terraform Configuration

#### Enable Karpenter in addons.tf
```terraform
# In infra/addons.tf
module "eks_blueprints_addons" {
  # ... existing configuration ...
  
  enable_karpenter = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }
  
  # Keep existing addons but plan to phase out managed node groups
}

# Add ECR public token for Karpenter images
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

# Virginia provider for ECR public
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}
```

#### Update EKS Configuration for Karpenter
```terraform
# In infra/eks/eks.tf - add to the EKS module
module "eks" {
  # ... existing configuration ...
  
  # Karpenter needs access to interrupt spot instances
  node_security_group_additional_rules = {
    karpenter_node_communication = {
      description = "Karpenter node communication"
      protocol    = "tcp"
      from_port   = 8443
      to_port     = 8443
      type        = "ingress"
      source_cluster_security_group = true
    }
  }
}
```

### 2. Create Karpenter NodePools

Create `k8s/karpenter/` directory structure:

```yaml
# k8s/karpenter/nodepool-general.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: general-purpose
spec:
  # Template for nodes
  template:
    metadata:
      labels:
        node-type: "general-purpose"
    spec:
      # Instance requirements
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64", "amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["m6g.medium", "m6g.large", "m6g.xlarge", "m6a.medium", "m6a.large", "m6a.xlarge"]
      
      # Node properties
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
      
      # Taints for specific workloads (optional)
      taints:
        - key: node-type
          value: general-purpose
          effect: NoSchedule
  
  # Limits
  limits:
    cpu: 1000
    memory: 1000Gi
  
  # Disruption settings
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
    expireAfter: 30m
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # AMI selection
  amiFamily: AL2
  
  # Subnets (will auto-discover based on tags)
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  
  # Security groups (will auto-discover)
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  
  # Instance profile
  instanceProfile: "KarpenterNodeInstanceProfile-${CLUSTER_NAME}"
  
  # User data for EKS
  userData: |
    #!/bin/bash
    /etc/eks/bootstrap.sh ${CLUSTER_NAME}
  
  # Block device mappings
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        deleteOnTermination: true
        encrypted: true
```

### 3. Migration Strategy

#### Phase 1: Parallel Deployment
1. Deploy Karpenter alongside existing node groups
2. Use node selectors and taints to test specific workloads
3. Monitor performance and costs

#### Phase 2: Gradual Migration
```yaml
# Example workload migration
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  template:
    spec:
      nodeSelector:
        node-type: "general-purpose"
      tolerations:
        - key: node-type
          value: general-purpose
          effect: NoSchedule
```

#### Phase 3: Complete Migration
1. Scale down existing node groups to minimum
2. Move all workloads to Karpenter nodes
3. Remove managed node groups from Terraform

### 4. Advanced Karpenter Configurations

#### Spot Instance Optimization
```yaml
# k8s/karpenter/nodepool-spot.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot-optimized
spec:
  template:
    metadata:
      labels:
        node-type: "spot"
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["m6g.large", "m6g.xlarge", "m6g.2xlarge", "m6a.large", "m6a.xlarge", "m6a.2xlarge", "c6g.large", "c6g.xlarge"]
      
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: spot-optimized
      
      taints:
        - key: spot-instance
          value: "true"
          effect: NoSchedule
  
  limits:
    cpu: 2000
    memory: 2000Gi
  
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5s
    expireAfter: 10m  # Shorter for spot instances
```

#### GPU NodePool (for ML workloads)
```yaml
# k8s/karpenter/nodepool-gpu.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: gpu-nodes
spec:
  template:
    metadata:
      labels:
        node-type: "gpu"
    spec:
      requirements:
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["g4dn.xlarge", "g4dn.2xlarge", "g5.xlarge", "g5.2xlarge"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
      
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: gpu-optimized
      
      taints:
        - key: nvidia.com/gpu
          value: "true"
          effect: NoSchedule
  
  limits:
    cpu: 1000
    memory: 1000Gi
```

### 5. Monitoring and Observability

#### Karpenter Metrics
Add to your Prometheus configuration:
```yaml
# Monitor Karpenter metrics
- job_name: 'karpenter'
  kubernetes_sd_configs:
    - role: endpoints
      namespaces:
        names:
          - karpenter
  relabel_configs:
    - source_labels: [__meta_kubernetes_service_name]
      action: keep
      regex: karpenter
```

#### Key Metrics to Monitor
- `karpenter_nodes_created_total`
- `karpenter_nodes_terminated_total`
- `karpenter_pod_startup_duration_seconds`
- `karpenter_cluster_state_sync_duration_seconds`

### 6. Cost Optimization Best Practices

1. **Use Mixed Instance Types**: Configure multiple instance families
2. **Leverage Spot Instances**: For fault-tolerant workloads
3. **Right-size Resources**: Use Karpenter's bin-packing efficiency
4. **Set Appropriate Limits**: Prevent runaway scaling costs
5. **Monitor Utilization**: Use consolidation policies effectively

### 7. Troubleshooting Common Issues

#### Node Provisioning Issues
```bash
# Check Karpenter logs
kubectl logs -n karpenter deployment/karpenter

# Check NodeClaim status
kubectl get nodeclaims

# Check events
kubectl get events -n karpenter
```

#### Instance Selection Problems
```bash
# Describe NodePool
kubectl describe nodepool general-purpose

# Check EC2NodeClass
kubectl describe ec2nodeclass default
```

### 8. Terraform Updates Required

#### Remove Managed Node Groups (Phase 3)
```terraform
# In infra/eks/eks.tf - comment out or remove
# eks_managed_node_groups = {
#   main = { ... }
#   spot = { ... }
# }
```

#### Add Karpenter IAM Policies
```terraform
# The EKS Blueprints addon will handle most IAM, but verify:
# - KarpenterNodeInstanceProfile
# - KarpenterControllerPolicy
# - Proper subnet and security group tags
```

### 9. Testing and Validation

#### Load Testing
```yaml
# Deploy a test workload to trigger scaling
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 100
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      containers:
      - name: inflate
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.2
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
```

### 10. Next Steps

1. **Week 1**: Enable Karpenter in Terraform, deploy basic NodePool
2. **Week 2**: Test with non-critical workloads, monitor metrics
3. **Week 3**: Gradually migrate production workloads
4. **Week 4**: Remove managed node groups, optimize configurations

This implementation will provide significant cost savings and operational improvements while maintaining the reliability of your EKS cluster.
