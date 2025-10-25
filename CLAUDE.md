# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a production-ready **Amazon EKS Cluster infrastructure** project combining Terraform IaC and Kubernetes GitOps. It provides a working implementation with comprehensive guides for progressive enhancement toward a cost-optimized, highly scalable architecture supporting 30-50% cost reduction through technologies like Karpenter, NLB, and Traefik.

**Key Technologies**: Terraform (AWS provider), EKS, Kubernetes 1.30, ArgoCD, Helm, Kustomize, kube-prometheus-stack

## Common Development Commands

Use the `just` task runner to manage Terraform operations across all modules:

```bash
# Initialize all Terraform modules (vpc → fck-nat → route53 → eks)
just init

# Plan all infrastructure changes
just plan

# Apply all infrastructure changes
just apply

# Destroy infrastructure in reverse order
just destroy
```

Individual module operations (if needed):
```bash
# For a specific module
cd infra/{module_name}
terraform init
terraform plan
terraform apply
```

Deploy Kubernetes manifests (after EKS cluster is up):
```bash
# ArgoCD manages all Kubernetes components via GitOps
# Apply ArgoCD first, then it manages everything else
kubectl apply -k k8s/argocd/
```

## Architecture Overview

### High-Level Structure

**Infrastructure Modules** (`infra/` directory):
- `vpc/`: Custom VPC with 3 AZs (10.0.0.0/16), public/private/database subnets
- `fck-nat/`: Cost-effective NAT alternative (cheaper than managed NAT Gateway)
- `route53/`: DNS zone management for aws.wiktorkowalski.pl domain
- `eks/`: EKS cluster v1.30 with managed node groups (ARM64 SPOT instances)

**State Management**: S3 backend with DynamoDB locking (bucket: `wiktorkowalski-terraform-state`)

### Key Infrastructure Decisions

1. **Multi-Module Architecture**: Each major component has separate state files for independence and reduced blast radius. Resources discovered via data sources and tags rather than direct module references (loose coupling).

2. **Cost Optimization by Default**:
   - ARM64 Graviton instances (m6g.medium/large) instead of x86
   - SPOT instances with 0 minimum scaling (scales to zero)
   - FCK-NAT instead of managed NAT Gateway (significant cost savings)
   - No managed NAT Gateway (default NAT disabled in VPC module)

3. **Multi-AZ HA Design**: All resources replicated across 3 AZs (eu-west-1a, eu-west-1b, eu-west-1c)

### Kubernetes/GitOps Components (`k8s/` directory)

- **ArgoCD**: GitOps controller for continuous deployment (self-healing enabled, auto-pruning)
- **kube-prometheus-stack**: Prometheus + Grafana monitoring
- **Metrics-server**: Resource metrics for HPA/VPA
- **Kubernetes Dashboard**: UI access to cluster
- **Addons**: AWS Load Balancer Controller, Cert Manager (for SSL automation)

**GitOps Pattern**: All components defined as ArgoCD Applications with Git as source of truth. Self-healing ensures cluster state matches Git.

## Important Files and Their Roles

| File | Purpose |
|------|---------|
| `infra/main.tf` | Root Terraform config: S3 backend, AWS provider, Terraform version constraint |
| `infra/locals.tf` | Cluster name definition (single source of truth: "eks-terraform") |
| `infra/addons.tf` | EKS Blueprints Addons: ALB Controller, Prometheus, ArgoCD, Cert Manager, External DNS |
| `infra/eks/eks.tf` | EKS cluster definition: v1.30, logging, managed node groups (main/spot), IAM |
| `infra/eks/data.tf` | Data sources for cross-module discovery: VPC lookup, subnet discovery, Route53 zone |
| `infra/vpc/vpc.tf` | VPC module config: 10.0.0.0/16, 3 AZs, Kubernetes subnet tagging |
| `k8s/argocd/kustomization.yml` | ArgoCD manifest patches (insecure server mode for dev) |
| `k8s/argocd/application.yml` | ArgoCD Application CRD (self-healing, auto-pruning) |
| `k8s/Installation.md` | Step-by-step deployment guide for local testing |
| `docs/00-EKS-CLUSTER-OVERVIEW.md` | Complete implementation roadmap and architecture decisions |

## Architecture Patterns and Conventions

### Terraform Patterns

1. **Data Source Discovery**: Modules use data sources to lookup resources by tags/names instead of direct references:
   - VPC discovered by name tag from data source (loose coupling)
   - Private subnets discovered by tags: `private=true`
   - Enables infrastructure changes without code updates

2. **Tag-Based Kubernetes Integration**:
   - VPC tagged with: `kubernetes.io/cluster/eks-terraform: owned`
   - Subnets tagged with: `kubernetes.io/role/elb: 1` or `kubernetes.io/role/internal-elb: 1`
   - Enables automatic ALB/NLB integration without manual configuration

3. **Version Pinning**: All provider and module versions are pinned for reproducible deployments

### Kubernetes/GitOps Patterns

1. **Kustomize Patching**: Use strategic merge patches for customization (e.g., ArgoCD insecure mode via kustomization patches)

2. **Self-Healing ArgoCD Applications**: All ArgoCD Applications configured with:
   - `automated.prune: true`: Remove resources deleted from Git
   - `automated.selfHeal: true`: Auto-sync on manual drift
   - Ensures Git is authoritative source of truth

3. **Namespace Isolation**: Each component in dedicated namespace (argocd, monitoring, kubernetes-dashboard)

## Development Guidelines

### When Modifying Terraform

1. **Understand the module layout**: Changes should respect the 5-module deployment order (vpc → fck-nat → route53 → eks)
2. **Update state management**: If adding new modules, ensure S3 backend configuration is added
3. **Use data sources**: Cross-module references should use data sources + tags, not direct references
4. **Pin versions**: Always pin provider and module versions for reproducibility
5. **Region handling**: Currently hardcoded to eu-west-1. TODO: move to variables for flexibility

### When Modifying Kubernetes Manifests

1. **Use Kustomize**: Modifications should use kustomization.yml patches, not direct manifest edits
2. **GitOps first**: All changes commit to Git; ArgoCD handles deployment
3. **Test locally first**: Use `k8s/Installation.md` guide to test on local Kubernetes before cluster deployment
4. **Namespace awareness**: Ensure components use appropriate namespace isolation

### When Adding Features

1. **Follow progression**: Refer to `docs/00-EKS-CLUSTER-OVERVIEW.md` for planned enhancement phases
2. **Document decisions**: Add comments explaining non-obvious infrastructure choices
3. **Cost-first mindset**: Consider cost implications of choices (e.g., instance types, node scaling)

## Current Known TODOs and Limitations

- **Hardcoded region**: `eu-west-1` hardcoded across modules; should be moved to Terraform variables
- **Hardcoded domain**: `aws.wiktorkowalski.pl` hardcoded in Route53; should be variable
- **Development configuration**: ArgoCD running in insecure mode (no HTTPS); production needs HTTPS config
- **AWS profile**: Hardcoded to "wiktorkowalski" personal AWS profile; consider parameterization

## Planned Architecture Enhancements

Comprehensive upgrade guides available in `docs/` directory (read in order):

1. **Karpenter** (`docs/01-KARPENTER-IMPLEMENTATION.md`): Replace managed node groups for 30-50% compute cost reduction
2. **NLB + Traefik** (`docs/02-NLB-TRAEFIK-INGRESS.md`): High-performance ingress with 20-30% ALB cost reduction
3. **Enhanced Monitoring** (`docs/03-GRAFANA-PROMETHEUS-LOKI-STACK.md`): Loki + Tempo integration for comprehensive observability

## Key Configuration Defaults

- **Cluster**: eks-terraform (v1.30)
- **Region**: eu-west-1 (3 AZs)
- **VPC CIDR**: 10.0.0.0/16
- **Node instances**: m6g.medium, m6g.large (ARM64 SPOT)
- **Node scaling**: 0-4 nodes (scales to zero for cost savings)
- **Backend**: S3 with DynamoDB locking
- **Terraform version**: >= 5.55.0
- **Kubernetes provider**: Auto-configured from EKS cluster auth token
