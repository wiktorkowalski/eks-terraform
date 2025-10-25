# Pre-Deployment Checklist

Complete these steps before deploying your EKS cluster.

## 1. Update Repository URLs

All ArgoCD Application CRDs reference the Git repository. Update the `repoURL` in these files to match your actual repository:

```bash
# Files to update:
# - k8s/argocd/apps/root-app.yaml
# - k8s/argocd-apps/argocd-app.yaml
# - k8s/argocd-apps/karpenter-app.yaml
# - k8s/argocd-apps/traefik-app.yaml
# - k8s/argocd-apps/cert-manager-app.yaml
# - k8s/argocd-apps/external-dns-app.yaml
# - k8s/argocd-apps/monitoring-app.yaml
# - k8s/argocd-apps/dashboard-app.yaml
# - k8s/monitoring/*.yaml

# Replace:
repoURL: https://github.com/wiktorkowalski/eks-terraform.git

# With your actual repo URL
```

### Quick Replace Command

```bash
cd /path/to/eks-terraform

# Replace with your repo URL
find k8s -name "*.yaml" -type f -exec sed -i '' \
  's|https://github.com/wiktorkowalski/eks-terraform.git|YOUR_REPO_URL|g' {} +
```

## 2. Verify AWS Configuration

```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify profile (if using named profile)
aws configure list --profile wiktorkowalski

# Check Route53 zone exists
aws route53 list-hosted-zones | grep "aws.wiktorkowalski.pl"
```

## 3. Update Email Addresses

Update contact email in these files:

- `k8s/traefik/base/configmap.yaml` (line: `email: contact@wiktorkowalski.pl`)
- `k8s/cert-manager/base/cluster-issuer.yaml` (line: `email: contact@wiktorkowalski.pl`)

```bash
# Quick replace
find k8s -name "*.yaml" -type f -exec sed -i '' \
  's|contact@wiktorkowalski.pl|your-email@example.com|g' {} +
```

## 4. Verify Domain Configuration

Ensure your Route53 hosted zone is properly configured:

```bash
# Check if zone exists
aws route53 list-hosted-zones-by-name --dns-name aws.wiktorkowalski.pl

# If not, create it (already defined in infra/route53/route53.tf)
# Will be created automatically during Terraform apply
```

## 5. Review Terraform Variables

Check these values in Terraform files:

- `infra/locals.tf`: `cluster_name = "eks-terraform"`
- `infra/main.tf`: `region = "eu-west-1"` and `profile = "wiktorkowalski"`
- `infra/route53/route53.tf`: Domain name

## 6. Commit Code to Git

ArgoCD requires all manifests to be in Git:

```bash
cd /path/to/eks-terraform

git status
git add .
git commit -m "feat: initial EKS cluster configuration"
git push origin main  # or master, depending on your default branch
```

## 7. Generate Monitoring Manifests (Optional)

If you want to deploy the monitoring stack immediately:

```bash
cd k8s/monitoring

# Follow instructions in README.md to generate:
# - prometheus-stack/base/manifests.yaml
# - grafana/base/manifests.yaml
# - loki/base/manifests.yaml
# - tempo/base/manifests.yaml
# - promtail/base/manifests.yaml

# Then commit to Git
git add .
git commit -m "feat: add monitoring stack manifests"
git push
```

## 8. Review Cost Estimates

Before deploying, understand the expected costs:

### Minimum Monthly Costs (with aggressive autoscaling)
- **EKS Control Plane**: $73/month
- **EC2 Instances** (Karpenter-managed):
  - Bootstrap node (t4g.small spot): ~$3/month (removed after 24-48h)
  - System nodes (2x m6g.large on-demand): ~$60/month
  - General nodes (varies with load, mostly spot): ~$30-100/month
- **NLB**: ~$20/month
- **fck-nat**: ~$0.50/month (EC2 t4g.nano)
- **EBS Volumes**: ~$10-30/month (monitoring, logs)
- **Route53**: ~$0.50/month (hosted zone)
- **Data Transfer**: Varies

**Total**: ~$200-300/month for a production-ready cluster with monitoring

### Comparison
- Traditional setup (without optimizations): $400-500/month
- **Savings**: 35-55% or $150-250/month

## 9. Pre-Flight Checks

```bash
# Terraform version
terraform version  # Should be >= 1.5.0

# kubectl version
kubectl version --client  # Should be >= 1.28

# Helm version
helm version  # Should be >= 3.12

# AWS CLI version
aws --version  # Should be >= 2.x

# just (task runner)
just --version  # Install if needed: brew install just
```

## 10. Backup Plan

Ensure you understand the rollback procedures:

- Full cluster destroy: `cd infra && just destroy`
- Partial rollback: Remove ArgoCD namespace
- Data backup: Configure Velero for cluster backups (post-deployment)

---

## Ready to Deploy?

Once all items are checked:

1. Run `just apply` from the `infra/` directory
2. Wait for infrastructure to be created (~30-45 minutes)
3. Follow `DEPLOYMENT-GUIDE.md` for ArgoCD bootstrap
4. Watch GitOps magic happen! ✨

---

## After Deployment

- [ ] Access ArgoCD UI and verify all apps are healthy
- [ ] Access Grafana and import dashboards
- [ ] Configure Alertmanager receivers (Slack, email)
- [ ] Deploy your first application via ArgoCD
- [ ] Remove bootstrap node after 24-48 hours
- [ ] Set up CI/CD pipeline for automatic deployments
- [ ] Configure backup strategy (Velero)
- [ ] Review and optimize resource requests/limits
- [ ] Set up cost monitoring in AWS Cost Explorer

---

## Need Help?

- Infrastructure issues: Review `docs/IMPLEMENTATION-OVERVIEW.md`
- Deployment issues: Review `DEPLOYMENT-GUIDE.md`
- Monitoring setup: Review `k8s/monitoring/README.md`
