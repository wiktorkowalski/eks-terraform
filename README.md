# EKS Cluster with Terraform

## Overview

This repository provides a comprehensive, production-ready Amazon EKS cluster implementation using Terraform and modern Kubernetes best practices. The project focuses on cost optimization, scalability, security, and operational excellence.

### Current Features
- **EKS Cluster**: v1.30 with managed node groups
- **VPC**: Custom VPC with public/private subnets across 3 AZs  
- **Monitoring**: kube-prometheus-stack via EKS Blueprints
- **GitOps**: ArgoCD for continuous deployment
- **DNS & SSL**: External DNS and Cert Manager integration
- **Load Balancing**: AWS Load Balancer Controller

### Planned Enhancements
This project includes comprehensive guides for upgrading to a more advanced, cost-effective architecture:

- **Karpenter**: Replace managed node groups with intelligent autoscaling
- **NLB + Traefik**: High-performance ingress with advanced routing
- **Enhanced Monitoring**: Grafana-Prometheus-Loki stack with Kustomize
- **Cost Optimization**: 30-50% reduction in infrastructure costs

## Architecture

### Current Architecture
![Current Architecture](https://github.com/user-attachments/assets/0a7dff9b-5611-4ceb-b60d-068974fc7eec)

### Target Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│                           AWS Cloud                            │
├─────────────────────────────────────────────────────────────────┤
│ Route53 → NLB → Traefik → EKS Cluster                         │
│                     ↓                                          │
│                 Karpenter                                      │
│                     ↓                                          │
│   ┌─────────────┬──────────────┬─────────────────────────────┐ │
│   │  Monitoring │   ArgoCD     │      Applications           │ │
│   │             │              │                             │ │
│   │ Prometheus  │   GitOps     │    - Your Apps              │ │
│   │ Grafana     │   Workflows  │    - Traefik                │ │
│   │ Loki        │              │    - Karpenter              │ │
│   │ AlertMgr    │              │    - External DNS           │ │
│   └─────────────┴──────────────┴─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm >= 3.12

### Deploy Current Infrastructure
```bash
# Clone the repository
git clone https://github.com/wiktorkowalski/eks-terraform.git
cd eks-terraform

# Deploy infrastructure
cd infra
terraform init
terraform plan
terraform apply

# Configure kubectl
aws eks update-kubeconfig --region eu-west-1 --name your-cluster-name

# Verify deployment
kubectl get nodes
kubectl get pods -A
```

## Implementation Guides

This repository includes comprehensive implementation guides for upgrading your EKS cluster:

### 📖 [Complete Implementation Overview](./docs/00-EKS-CLUSTER-OVERVIEW.md)
Start here for a comprehensive overview of the entire implementation roadmap.

### 🚀 [1. Karpenter Implementation](./docs/01-KARPENTER-IMPLEMENTATION.md)
Replace managed node groups with Karpenter for:
- 30-50% cost reduction
- Sub-minute node provisioning
- Better instance type diversity
- Simplified management

### 🌐 [2. NLB + Traefik Ingress](./docs/02-NLB-TRAEFIK-INGRESS.md)
Implement high-performance ingress with:
- 20-30% load balancer cost reduction
- Lower latency (Layer 4 vs Layer 7)
- Advanced traffic management
- TCP/UDP protocol support

### 📊 [3. Grafana-Prometheus-Loki Stack](./docs/03-GRAFANA-PROMETHEUS-LOKI-STACK.md)
Enhanced monitoring with Kustomize for:
- GitOps-ready configuration management
- Environment-specific monitoring configs
- Comprehensive observability
- Custom dashboards and alerts

## Key Benefits

### Cost Optimization
- **30-50% compute cost reduction** with Karpenter
- **20-30% load balancer cost reduction** with NLB
- **Intelligent spot instance usage** with fault tolerance
- **Automated resource right-sizing**

### Performance Improvements
- **Sub-minute node provisioning** vs 3-5 minutes
- **Lower latency** with Layer 4 load balancing
- **Better resource utilization** with bin-packing
- **Advanced traffic routing** capabilities

### Operational Excellence
- **Everything as code** with GitOps
- **Comprehensive monitoring** and alerting
- **Reduced manual operations**
- **Consistent configuration management**

## Project Structure

```
eks-terraform/
├── docs/                          # Implementation guides
│   ├── 00-EKS-CLUSTER-OVERVIEW.md # Complete overview
│   ├── 01-KARPENTER-IMPLEMENTATION.md
│   ├── 02-NLB-TRAEFIK-INGRESS.md
│   └── 03-GRAFANA-PROMETHEUS-LOKI-STACK.md
├── infra/                         # Terraform infrastructure
│   ├── main.tf                    # Provider configuration
│   ├── addons.tf                  # EKS addons and blueprints
│   ├── eks/                       # EKS cluster configuration
│   ├── vpc/                       # VPC and networking
│   ├── route53/                   # DNS configuration
│   └── acm/                       # SSL certificates
├── k8s/                          # Kubernetes manifests
│   ├── argocd/                   # GitOps configuration
│   ├── monitoring/               # Monitoring stack (future)
│   ├── traefik/                  # Ingress controller (future)
│   └── karpenter/                # Node autoscaler (future)
└── README.md                     # This file
```

## Getting Started with Improvements

1. **Read the Overview**: Start with [docs/00-EKS-CLUSTER-OVERVIEW.md](./docs/00-EKS-CLUSTER-OVERVIEW.md)
2. **Plan Your Implementation**: Review each guide and plan your timeline
3. **Start with Karpenter**: Begin with the highest-impact improvement
4. **Proceed Incrementally**: Implement each component step by step
5. **Monitor and Optimize**: Continuously improve based on metrics

## Support and Contributing

### Issues and Questions
- Check the troubleshooting sections in each guide
- Review common issues and solutions
- Open GitHub issues for bugs or questions

### Contributing
- Fork the repository
- Create feature branches for improvements
- Submit pull requests with detailed descriptions
- Follow the existing code and documentation style

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Additional Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Karpenter Documentation](https://karpenter.sh/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Operator](https://prometheus-operator.dev/)
