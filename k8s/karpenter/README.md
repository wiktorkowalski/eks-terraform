# Karpenter GitOps Setup

Karpenter is deployed via ArgoCD using the official Helm chart + NodePool/EC2NodeClass manifests from Git.

## Architecture

- **Terraform (infra/eks/)**: Creates IAM roles, SQS queue, EventBridge rules
- **ArgoCD + Helm**: Deploys Karpenter controller
- **Git (k8s/karpenter/nodepools/)**: NodePools and EC2NodeClasses

## Setup Steps

### 1. Apply Terraform

```bash
cd infra
just apply
```

This creates:
- Karpenter controller IAM role (`eks-terraform-karpenter-controller`)
- Karpenter node IAM role (`KarpenterNodeRole-eks-terraform`)
- SQS queue for spot interruption (`eks-terraform-karpenter`)
- EventBridge rules for instance lifecycle events

### 2. Get Dynamic Values

After Terraform completes, retrieve the values needed for Karpenter:

```bash
# Get cluster endpoint
aws eks describe-cluster --name eks-terraform --region eu-west-1 \
  --query 'cluster.endpoint' --output text

# Get Karpenter controller IAM role ARN
cd infra/eks
terraform output karpenter_controller_role_arn
```

### 3. Update Karpenter ArgoCD Application

Edit `k8s/argocd-apps/karpenter-app.yaml` and update these values:

```yaml
settings:
  clusterEndpoint: "https://YOUR_CLUSTER_ENDPOINT"  # From step 2
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT:role/eks-terraform-karpenter-controller"  # From step 2
```

### 4. Commit and Deploy

```bash
git add k8s/argocd-apps/karpenter-app.yaml
git commit -m "feat: configure Karpenter with cluster values"
git push
```

### 5. Bootstrap ArgoCD

```bash
kubectl apply -k k8s/argocd/base/
kubectl apply -k k8s/argocd/apps/
```

ArgoCD will automatically deploy Karpenter and the NodePools!

## NodePools

Three NodePools are pre-configured in `k8s/karpenter/nodepools/`:

### 1. general-purpose
- **Purpose**: Web apps, APIs, microservices
- **Instances**: t4g, m6g, m6a (medium, large, xlarge)
- **Architecture**: ARM64 + x86
- **Capacity**: Spot-first (on-demand fallback)
- **Labels**: `workload-type: general`
- **Taints**: None
- **Use**: Default for most workloads

### 2. stateful
- **Purpose**: Databases, caches, persistent data
- **Instances**: m6g, m5, r6g (large, xlarge, 2xlarge)
- **Architecture**: ARM64 + x86
- **Capacity**: On-demand only
- **Labels**: `workload-type: stateful`
- **Taints**: `workload-type=stateful:NoSchedule`
- **Use**: Requires nodeSelector + toleration

### 3. system
- **Purpose**: Monitoring, ArgoCD, system components
- **Instances**: m6g (large, xlarge, 2xlarge)
- **Architecture**: ARM64 only
- **Capacity**: On-demand only
- **Labels**: `workload-type: system`
- **Taints**: `workload-type=system:NoSchedule`
- **Use**: Requires nodeSelector + toleration

## Usage Examples

### Deploy to General NodePool (Default)

No special configuration needed - pods will automatically schedule here.

### Deploy to Stateful NodePool

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  template:
    spec:
      nodeSelector:
        workload-type: stateful
      tolerations:
        - key: workload-type
          value: stateful
          effect: NoSchedule
```

### Deploy to System NodePool

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
spec:
  template:
    spec:
      nodeSelector:
        workload-type: system
      tolerations:
        - key: workload-type
          value: system
          effect: NoSchedule
```

## Verification

```bash
# Check Karpenter is running
kubectl get pods -n karpenter

# Check NodePools created
kubectl get nodepools -n karpenter

# Watch Karpenter provision nodes
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# See provisioned nodes
kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type
```

## Troubleshooting

### Karpenter pods not starting

Check IAM role annotation:
```bash
kubectl get sa -n karpenter karpenter -o yaml | grep eks.amazonaws.com/role-arn
```

### Nodes not provisioning

Check Karpenter logs:
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100
```

Common issues:
- IAM role not attached correctly
- Subnet tags missing (`karpenter.sh/discovery: eks-terraform`)
- Security group tags missing
- Instance profile creation permissions

### Verify IAM setup

```bash
# Check controller role
aws iam get-role --role-name eks-terraform-karpenter-controller

# Check node role
aws iam get-role --role-name KarpenterNodeRole-eks-terraform

# Check SQS queue
aws sqs get-queue-url --queue-name eks-terraform-karpenter
```

## Cost Optimization Tips

1. **Prioritize Spot**: General NodePool uses spot-first strategy
2. **Right-size limits**: Adjust NodePool limits based on workload
3. **Consolidation**: Karpenter automatically consolidates underutilized nodes
4. **TTL**: General nodes expire after 30 days (force instance refresh)

## References

- [Karpenter Documentation](https://karpenter.sh/)
- [Karpenter Best Practices](https://aws.github.io/aws-eks-best-practices/karpenter/)
- [NodePool API Reference](https://karpenter.sh/docs/concepts/nodepools/)
