# EKS Cluster Deployment Guide

This guide walks you through deploying a production-ready EKS cluster with Karpenter, GitOps (ArgoCD), and full observability.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm >= 3.12 (for generating monitoring manifests)
- Git access to this repository
- Route53 hosted zone: `aws.wiktorkowalski.pl`

## Architecture Summary

- **Compute**: EKS 1.30 with Karpenter autoscaling (3 NodePools: general-purpose, stateful, system)
- **Networking**: Single NLB + Traefik DaemonSet + fck-nat (cost-optimized)
- **GitOps**: ArgoCD with app-of-apps pattern (everything in Git)
- **Ingress**: Traefik with Let's Encrypt (DNS-01 via Route53)
- **Monitoring**: Prometheus, Grafana, Loki, Tempo, Promtail
- **Cost Savings**: 35-55% vs traditional setup

---

## Phase 1: Deploy Infrastructure (30-45 minutes)

### Step 1: Apply Terraform

```bash
cd /path/to/eks-terraform

# Initialize and apply all modules
just init
just plan
just apply

# Expected duration: 30-45 minutes
# EKS cluster creation takes ~20 minutes
```

### Step 2: Verify Infrastructure

```bash
# Check NLB created
aws elbv2 describe-load-balancers --names eks-terraform-traefik-nlb

# Check Karpenter IAM role
aws iam list-roles | grep Karpenter

# Check Route53 wildcard record
dig +short grafana.aws.wiktorkowalski.pl
```

---

## Phase 2: Bootstrap ArgoCD (10 minutes)

### Step 1: Configure kubectl

```bash
aws eks update-kubeconfig --name eks-terraform --region eu-west-1
kubectl get nodes  # Verify connectivity - should see 1 bootstrap node
```

### Step 2: Install ArgoCD

```bash
# Apply ArgoCD bootstrap manifests
kubectl apply -k k8s/argocd/base/

# Wait for ArgoCD to be ready (2-3 minutes)
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
```

### Step 3: Deploy Root App-of-Apps

```bash
# Deploy the root app (triggers all other apps)
kubectl apply -k k8s/argocd/apps/

# Verify root app created
kubectl get application -n argocd root
```

### Step 4: Access ArgoCD UI

```bash
# Port-forward to ArgoCD (until Traefik is ready)
kubectl port-forward -n argocd svc/argocd-server 8080:443 &

# Open in browser
open https://localhost:8080

# Login with:
# Username: admin
# Password: (from step 2)
```

---

## Phase 3: Watch GitOps Deploy Everything (20-30 minutes)

ArgoCD will automatically sync and deploy all applications. Monitor progress in the UI or CLI:

```bash
# Watch all applications sync
watch kubectl get applications -n argocd

# Expected applications:
# - argocd (self-managed)
# - karpenter (NodePools)
# - traefik (Ingress)
# - cert-manager (TLS)
# - external-dns (Route53)
# - monitoring (Prometheus, Grafana, etc.)
# - kubernetes-dashboard

# Check Karpenter nodes being provisioned
watch kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type

# Check pods across all namespaces
kubectl get pods --all-namespaces
```

---

## Phase 4: Configure Monitoring Stack (Optional but Recommended)

The monitoring stack requires Helm manifests to be generated. See `k8s/monitoring/README.md` for detailed instructions.

### Quick Setup

```bash
cd k8s/monitoring

# 1. Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 2. Follow README.md to generate manifests for each component
# 3. Commit generated manifests to Git
# 4. ArgoCD will auto-sync and deploy

# Alternatively: Use ArgoCD with Helm sources directly
# (modify Application CRDs to use Helm chart repos instead of Git paths)
```

---

## Phase 5: Access Services

Once all applications are synced and healthy:

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD | https://argocd.aws.wiktorkowalski.pl | admin / (from secret) |
| Grafana | https://grafana.aws.wiktorkowalski.pl | admin / (from secret `grafana-admin-secret`) |
| Prometheus | https://prometheus.aws.wiktorkowalski.pl | No auth |
| Alertmanager | https://alertmanager.aws.wiktorkowalski.pl | No auth |
| Kubernetes Dashboard | https://dashboard.aws.wiktorkowalski.pl | Token-based |

### Get Kubernetes Dashboard Token

```bash
kubectl -n kubernetes-dashboard create token admin-user
# Copy token and use in dashboard login
```

---

## Phase 6: Cleanup Bootstrap Node (After 24-48h)

After verifying Karpenter is managing all workloads:

```bash
# 1. Verify no critical pods on bootstrap node
kubectl get pods --all-namespaces -o wide | grep bootstrap

# 2. Check Karpenter nodes running workloads
kubectl get nodes -L karpenter.sh/nodepool

# 3. Edit infra/eks/eks.tf and remove bootstrap node group
# Change eks_managed_node_groups to empty: {}

# 4. Apply change
cd infra
just apply
```

---

## Validation

### Infrastructure Health

```bash
# All ArgoCD apps synced and healthy
kubectl get applications -n argocd

# Karpenter NodePools created
kubectl get nodepools -n karpenter

# All nodes registered
kubectl get nodes

# DNS resolving correctly
dig +short argocd.aws.wiktorkowalski.pl
dig +short grafana.aws.wiktorkowalski.pl
```

### Service Health

```bash
# Traefik running on all nodes
kubectl get pods -n traefik-system -o wide

# Cert-Manager issuer ready
kubectl get clusterissuer letsencrypt

# External-DNS running
kubectl get pods -n external-dns

# Check TLS certificates
kubectl get certificates --all-namespaces
```

---

## Troubleshooting

### ArgoCD Apps Not Syncing

```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Force sync an application
kubectl patch application -n argocd <app-name> --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### Karpenter Not Provisioning Nodes

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Check NodePool status
kubectl describe nodepool -n karpenter general-purpose

# Verify IAM role and subnet tags
aws iam get-role --role-name KarpenterNodeRole-eks-terraform
aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=eks-terraform"
```

### TLS Certificates Not Issuing

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate status
kubectl describe certificate -n argocd argocd-tls

# Check Let's Encrypt challenge
kubectl get challenges --all-namespaces
```

### NLB Health Checks Failing

```bash
# Check NLB target health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
  --names eks-terraform-traefik-http --query 'TargetGroups[0].TargetGroupArn' --output text)

# Check Traefik /ping endpoint
kubectl port-forward -n traefik-system ds/traefik 8080:8080
curl http://localhost:8080/ping
```

---

## Cost Optimization

### Current Setup Savings

- **Karpenter**: 30-50% reduction in compute costs (intelligent instance selection + spot)
- **NLB vs ALB**: 20-30% savings on load balancer costs
- **fck-nat**: ~90% savings vs NAT Gateway (~$32/month vs ~$0.50/month)
- **ARM64 Graviton**: 20% cheaper than x86 equivalent instances
- **Total**: 35-55% infrastructure cost reduction

### Further Optimizations

1. **Enable S3 backend for Loki**: Reduce EBS costs for log storage
2. **Use Fargate for ArgoCD**: Eliminate bootstrap node completely
3. **Implement HPA**: Auto-scale stateless workloads based on load
4. **Configure cluster autoscaler**: Scale down idle Karpenter nodes

---

## Next Steps

1. **Configure Alertmanager**: Set up Slack/email receivers
2. **Import Grafana Dashboards**: Add pre-built dashboards for Kubernetes monitoring
3. **Deploy Your Applications**: Use ArgoCD to deploy your workloads
4. **Set up CI/CD**: Integrate with GitHub Actions or GitLab CI
5. **Configure Backup**: Set up Velero for cluster backups

---

## Rollback Procedures

### Complete Rollback

```bash
# Destroy entire cluster
cd infra
just destroy

# Confirm all resources deleted in AWS Console
```

### Partial Rollback (Keep Cluster)

```bash
# Remove all ArgoCD apps
kubectl delete applications --all -n argocd

# Remove ArgoCD
kubectl delete namespace argocd

# Optionally remove Kubernetes manifests from Git
```

---

## Support

- **Infrastructure Issues**: Check `infra/` Terraform files and `docs/IMPLEMENTATION-OVERVIEW.md`
- **Kubernetes Issues**: Check `k8s/` manifests and ArgoCD logs
- **Monitoring Issues**: See `k8s/monitoring/README.md`

For questions or issues, refer to:
- AWS EKS Documentation: https://docs.aws.amazon.com/eks/
- Karpenter Documentation: https://karpenter.sh/
- ArgoCD Documentation: https://argo-cd.readthedocs.io/
