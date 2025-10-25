# EKS GitOps Implementation Overview

**Goal**: Production-ready EKS cluster with full GitOps, cost-optimized autoscaling, and complete observability

**Deployment Type**: Fresh cluster deployment (no migration needed)
**Cost Savings**: 35-55% reduction in infrastructure costs vs traditional setup
**Timeline**: 2-4 hours for infrastructure + GitOps setup

---

## Table of Contents
- [Architecture Summary](#architecture-summary)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Implementation Phases](#implementation-phases)
- [Component Details](#component-details)
- [GitOps Workflow](#gitops-workflow)
- [Access URLs](#access-urls)
- [Success Metrics](#success-metrics)
- [Validation](#validation)
- [Rollback Procedures](#rollback-procedures)

---

## Architecture Summary

### Final Architecture
```
Internet
   ↓
Route53 (*.aws.wiktorkowalski.pl)
   ↓
Network Load Balancer (TCP 80/443)
   ↓
Traefik DaemonSet (all nodes, NodePort 30080/30443)
   ├── TLS termination (Cert-Manager + Let's Encrypt)
   ├── HTTP → HTTPS redirect
   └── IngressRoute CRDs
   ↓
┌────────────────────────────────────────────────────────────┐
│              EKS Cluster (Kubernetes 1.30)                 │
├────────────────────────────────────────────────────────────┤
│  Node Management: Karpenter                                │
│  ├── general-purpose (spot, ARM64+x86) - web apps/APIs    │
│  ├── stateful (on-demand, memory) - databases/caches      │
│  └── system (on-demand, stable) - monitoring/ArgoCD       │
│                                                            │
│  GitOps: ArgoCD (app-of-apps pattern)                     │
│  ├── argocd/ (self-managed)                               │
│  ├── karpenter/ (NodePools)                               │
│  ├── traefik/ (DaemonSet)                                 │
│  ├── cert-manager/ (Let's Encrypt)                        │
│  ├── monitoring/ (observability stack)                    │
│  └── kubernetes-dashboard/                                │
│                                                            │
│  Observability:                                            │
│  - Metrics: Prometheus → Grafana                          │
│  - Logs: Promtail → Loki → Grafana                       │
│  - Traces: Tempo → Grafana                                │
│  - Alerts: Alertmanager → Slack/Email                    │
└────────────────────────────────────────────────────────────┘
```

### Core Components
- **Node Autoscaling**: Karpenter (replaces EKS managed node groups)
- **Ingress**: NLB + Traefik DaemonSet with IngressRoute CRDs
- **GitOps**: ArgoCD with app-of-apps pattern (self-managed)
- **Observability**: kube-prometheus-stack + Loki + Tempo + Promtail
- **TLS**: Cert-Manager + Let's Encrypt (DNS challenge via Route53)

### Key Decisions
- ✅ **Fresh deployment** - No migration, clean architecture from day 1
- ✅ Kustomize manifests in Git, deployed via ArgoCD
- ✅ Traefik DaemonSet on all nodes (NodePort 30080/30443)
- ✅ ArgoCD self-managed (bootstrap via `kubectl apply`)
- ✅ **All components via GitOps** - No EKS Blueprints addons except Karpenter + metrics-server
- ✅ Native Karpenter node registration (no Lambda)
- ✅ **Small bootstrap node** (t4g.small) for initial setup, removed after 24-48h
- ✅ Traefik IngressRoute CRDs (not standard Ingress)
- ✅ Kubernetes Dashboard included
- ✅ kube-prometheus-stack pre-rendered from Helm to Kustomize YAML
- ✅ 3 NodePools: general-purpose, stateful, system (no GPU initially)

---

## Prerequisites

### Technical Requirements
- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm >= 3.12 (for rendering charts to YAML)
- kustomize >= 5.0
- Git access to repository

### AWS Permissions Required
- EKS cluster management (create/update/delete clusters)
- EC2 instance and networking (VPC, subnets, security groups, NLB)
- IAM role creation and management
- Route53 DNS zone management
- S3 access for Terraform state (bucket: `wiktorkowalski-terraform-state`)

### Knowledge Requirements
- Kubernetes fundamentals (pods, deployments, services, ingress)
- Terraform basics (modules, state, providers)
- AWS networking concepts (VPC, subnets, load balancers)
- GitOps workflow understanding
- Kustomize basics

---

## Repository Structure

```
eks-terraform/
├── infra/                          # Terraform (Infrastructure as Code)
│   ├── main.tf                     # Backend, provider, version constraints
│   ├── locals.tf                   # Cluster name
│   ├── addons.tf                   # EKS Blueprints (Karpenter only)
│   ├── output.tf
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── vpc.tf                  # VPC with Karpenter tags
│   │   └── locals.tf
│   ├── eks/
│   │   ├── main.tf
│   │   ├── eks.tf                  # EKS cluster + Karpenter SG rules
│   │   ├── nlb.tf                  # NEW: NLB + target groups
│   │   ├── data.tf                 # VPC/subnet discovery
│   │   └── locals.tf
│   ├── fck-nat/
│   │   ├── main.tf
│   │   └── fck_nat.tf
│   └── route53/
│       ├── main.tf
│       └── route53.tf              # Wildcard record for NLB
│
└── k8s/                            # Kubernetes manifests (GitOps)
    ├── argocd/
    │   ├── base/                   # ArgoCD installation
    │   │   ├── namespace.yaml
    │   │   ├── install.yaml        # Official ArgoCD manifests
    │   │   ├── ingress-route.yaml  # https://argocd.aws.wiktorkowalski.pl
    │   │   └── kustomization.yaml
    │   └── apps/
    │       ├── root-app.yaml       # App-of-apps root
    │       └── kustomization.yaml
    │
    ├── argocd-apps/                # ArgoCD Application definitions
    │   ├── kustomization.yaml
    │   ├── argocd-app.yaml         # ArgoCD self-management
    │   ├── karpenter-app.yaml
    │   ├── traefik-app.yaml
    │   ├── cert-manager-app.yaml
    │   ├── monitoring-app.yaml     # App-of-apps for monitoring stack
    │   └── dashboard-app.yaml
    │
    ├── karpenter/
    │   └── base/
    │       ├── namespace.yaml
    │       ├── nodepool-general.yaml
    │       ├── nodepool-stateful.yaml
    │       ├── nodepool-system.yaml
    │       ├── ec2nodeclass-general.yaml
    │       ├── ec2nodeclass-stateful.yaml
    │       ├── ec2nodeclass-system.yaml
    │       └── kustomization.yaml
    │
    ├── traefik/
    │   ├── base/
    │   │   ├── namespace.yaml
    │   │   ├── rbac.yaml
    │   │   ├── daemonset.yaml
    │   │   ├── service.yaml        # NodePort 30080/30443
    │   │   ├── configmap.yaml      # Traefik config (Let's Encrypt DNS)
    │   │   └── kustomization.yaml
    │   └── config/
    │       ├── middleware-secure-headers.yaml
    │       ├── middleware-redirect-https.yaml
    │       ├── middleware-rate-limit.yaml
    │       ├── middleware-compress.yaml
    │       ├── tls-options.yaml
    │       └── ingressroutes/
    │           ├── argocd.yaml
    │           ├── grafana.yaml
    │           ├── prometheus.yaml
    │           ├── alertmanager.yaml
    │           └── dashboard.yaml
    │
    ├── cert-manager/
    │   └── base/
    │       ├── namespace.yaml
    │       ├── install.yaml         # cert-manager CRDs + components
    │       ├── cluster-issuer.yaml  # Let's Encrypt production
    │       └── kustomization.yaml
    │
    ├── monitoring/
    │   ├── kustomization.yaml       # App-of-apps for monitoring
    │   ├── prometheus-stack/
    │   │   └── base/
    │   │       ├── namespace.yaml
    │   │       ├── crds.yaml        # Prometheus Operator CRDs
    │   │       ├── operator.yaml    # Prometheus Operator
    │   │       ├── prometheus.yaml  # Prometheus StatefulSet
    │   │       ├── alertmanager.yaml
    │   │       ├── node-exporter.yaml
    │   │       ├── kube-state-metrics.yaml
    │   │       ├── servicemonitors.yaml
    │   │       └── kustomization.yaml
    │   ├── grafana/
    │   │   └── base/
    │   │       ├── deployment.yaml
    │   │       ├── configmap-datasources.yaml
    │   │       ├── configmap-dashboards.yaml  # Dashboard IDs
    │   │       ├── secret.yaml
    │   │       ├── pvc.yaml
    │   │       ├── service.yaml
    │   │       └── kustomization.yaml
    │   ├── loki/
    │   │   └── base/
    │   │       ├── statefulset-read.yaml
    │   │       ├── statefulset-write.yaml
    │   │       ├── deployment-gateway.yaml
    │   │       ├── configmap.yaml
    │   │       ├── service-*.yaml
    │   │       └── kustomization.yaml
    │   ├── tempo/
    │   │   └── base/
    │   │       ├── statefulset.yaml
    │   │       ├── configmap.yaml
    │   │       ├── service.yaml
    │   │       └── kustomization.yaml
    │   └── promtail/
    │       └── base/
    │           ├── daemonset.yaml
    │           ├── configmap.yaml
    │           ├── service.yaml
    │           └── kustomization.yaml
    │
    └── kubernetes-dashboard/
        └── base/
            ├── namespace.yaml
            ├── install.yaml
            ├── ingress-route.yaml
            └── kustomization.yaml
```

---

## Implementation Phases

**Simplified 2-Phase Approach** - Fresh deployment with no migration

### Phase 1: Terraform Infrastructure (30-45 minutes)

**Objective**: Deploy complete EKS infrastructure with Karpenter and NLB

**What Gets Deployed:**

1. **EKS Cluster** (Kubernetes 1.30)
   - 1 small bootstrap node (t4g.small SPOT) with taint
   - Karpenter enabled via EKS Blueprints
   - Metrics-server enabled
   - All other addons disabled (deployed via ArgoCD)

2. **Network Load Balancer**
   - Public-facing NLB in public subnets
   - Target groups for HTTP (30080) and HTTPS (30443)
   - TCP listeners on ports 80 and 443
   - Health checks to Traefik `/ping`
   - Bootstrap node auto-registered to target groups

3. **VPC Tagging**
   - Subnets tagged with `karpenter.sh/discovery`
   - Security groups tagged for Karpenter

4. **Route53**
   - Wildcard A record: `*.aws.wiktorkowalski.pl` → NLB

**Terraform Files Modified:**
- ✅ `infra/main.tf` - Added us-east-1 provider + ECR auth token
- ✅ `infra/addons.tf` - Enabled Karpenter only, disabled all other addons
- ✅ `infra/eks/eks.tf` - Bootstrap node + Karpenter security group rules
- ✅ `infra/eks/nlb.tf` - NEW: NLB with target groups
- ✅ `infra/eks/data.tf` - Added public subnets data source
- ✅ `infra/vpc/vpc.tf` - Added Karpenter discovery tags
- ✅ `infra/route53/data.tf` - NEW: NLB lookup data source
- ✅ `infra/route53/route53.tf` - Wildcard DNS record

**Apply Infrastructure:**
```bash
cd /path/to/eks-terraform
just apply  # Runs terraform init + plan + apply across all modules
```

**Expected Duration:** 30-45 minutes (EKS cluster creation takes ~15-20 mins)

**Deliverables:**
- ✅ EKS cluster running with 1 bootstrap node
- ✅ Karpenter installed and ready
- ✅ NLB created and healthy
- ✅ DNS wildcard record active
- ✅ Ready for ArgoCD bootstrap

---

### Phase 2: ArgoCD Bootstrap + GitOps (Auto-deploys everything)

**Objective**: Bootstrap ArgoCD, then let GitOps deploy all remaining components

**Duration:** 5-10 minutes manual work + 20-30 minutes auto-deployment

**Steps:**

1. **Configure kubectl** (if not already):
   ```bash
   aws eks update-kubeconfig --name eks-terraform --region eu-west-1
   kubectl get nodes  # Verify connectivity
   ```

2. **Create ArgoCD manifests** (once, in Git):
   ```bash
   # Structure already defined in docs/IMPLEMENTATION-OVERVIEW.md
   # Create k8s/argocd/base/ and k8s/argocd/apps/
   ```

3. **Bootstrap ArgoCD** (one-time manual kubectl):
   ```bash
   kubectl apply -k k8s/argocd/base/

   # Wait for ArgoCD ready
   kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

   # Get admin password
   kubectl -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath="{.data.password}" | base64 -d
   ```

4. **Deploy root app-of-apps** (enables GitOps for everything):
   ```bash
   kubectl apply -k k8s/argocd/apps/
   ```

5. **Watch ArgoCD auto-deploy everything**:
   ```bash
   # Port-forward to ArgoCD UI
   kubectl port-forward -n argocd svc/argocd-server 8080:443

   # Open https://localhost:8080
   # Login with admin + password from step 3
   # Watch all applications sync automatically
   ```

**What ArgoCD Auto-Deploys:**

From `k8s/argocd-apps/` directory:
- ✅ **ArgoCD** (self-managed)
- ✅ **Karpenter** - 3 NodePools (general, stateful, system)
- ✅ **Traefik** - DaemonSet with middlewares + IngressRoutes
- ✅ **Cert-Manager** - Let's Encrypt ClusterIssuer
- ✅ **Monitoring** - Prometheus, Grafana, Loki, Tempo, Promtail, Alertmanager
- ✅ **Kubernetes Dashboard**

**Deliverables:**
- ✅ All infrastructure components running
- ✅ Karpenter provisioning nodes automatically
- ✅ Traefik handling ingress with TLS
- ✅ All services accessible via HTTPS
- ✅ Complete observability stack operational

---

### Phase 3: Cleanup Bootstrap Node (After 24-48 hours)

**Objective**: Remove temporary bootstrap node after Karpenter is stable

**When:** After verifying:
- Karpenter has provisioned nodes successfully
- All workloads running on Karpenter nodes
- No pods scheduled on bootstrap node (due to taint)

**Steps:**
1. **Verify Karpenter is healthy**:
   ```bash
   kubectl get nodepools
   kubectl get nodes -L karpenter.sh/nodepool
   kubectl get pods --all-namespaces -o wide | grep bootstrap
   # Should see no pods on bootstrap node (except DaemonSets with toleration)
   ```

2. **Remove bootstrap node group**:
   ```terraform
   # Edit infra/eks/eks.tf
   # Delete or comment out the entire eks_managed_node_groups block
   eks_managed_node_groups = {}  # Empty!
   ```

3. **Apply change**:
   ```bash
   just apply
   ```

**Deliverables:**
- ✅ 100% Karpenter-managed infrastructure
- ✅ No managed node groups remaining
- ✅ Full cost savings realized

---

## Component Details

### Karpenter NodePools

#### 1. general-purpose NodePool
**Purpose**: Web applications, APIs, microservices

**Configuration:**
- Instance types: `t4g`, `m6g`, `m6a` (medium, large, xlarge)
- Architecture: ARM64 + x86 (multi-arch)
- Capacity: Spot-first (80%), on-demand fallback (20%)
- Scaling: Aggressive consolidation (30s), expires after 30 days
- Labels: `workload-type: general`
- Limits: 1000 CPU, 1000Gi memory

**Usage in workloads:**
```yaml
nodeSelector:
  workload-type: general
```

#### 2. stateful NodePool
**Purpose**: Databases, caches, persistent workloads

**Configuration:**
- Instance types: `m6g`, `m5`, `r6g` (large, xlarge, 2xlarge)
- Architecture: ARM64 + x86 (multi-arch)
- Capacity: On-demand only (for stability)
- Scaling: Conservative (WhenEmpty after 5m), never expires
- Labels: `workload-type: stateful`
- Taints: `workload-type=stateful:NoSchedule`
- Limits: 500 CPU, 500Gi memory

**Usage in workloads:**
```yaml
nodeSelector:
  workload-type: stateful
tolerations:
  - key: workload-type
    value: stateful
    effect: NoSchedule
```

#### 3. system NodePool
**Purpose**: Monitoring, ArgoCD, critical system components

**Configuration:**
- Instance types: `m6g` (large, xlarge, 2xlarge)
- Architecture: ARM64 only (cost savings)
- Capacity: On-demand only (predictable)
- Scaling: Conservative (WhenEmpty after 10m), never expires
- Labels: `workload-type: system`
- Taints: `workload-type=system:NoSchedule`
- Limits: 200 CPU, 200Gi memory

**Usage in workloads:**
```yaml
nodeSelector:
  workload-type: system
tolerations:
  - key: workload-type
    value: system
    effect: NoSchedule
```

### Karpenter Metrics to Monitor
- `karpenter_nodes_created_total` - Node provisioning rate
- `karpenter_nodes_terminated_total` - Node termination rate
- `karpenter_pod_startup_duration_seconds` - Pod scheduling latency
- `karpenter_cluster_state_sync_duration_seconds` - Karpenter performance

---

### Traefik Configuration

#### DaemonSet Strategy
- **Why DaemonSet**: One Traefik pod per node ensures all nodes receive NLB traffic
- **NodePort**: 30080 (HTTP), 30443 (HTTPS), 30808 (dashboard/metrics)
- **Tolerations**: Runs on all NodePools (general, stateful, system)
- **Affinity**: Prefers general-purpose nodes

#### TLS Termination
- Traefik terminates TLS (not NLB)
- Cert-Manager provides certificates via Let's Encrypt DNS-01 challenge
- Route53 integration for DNS validation

#### HTTP to HTTPS Redirect
Automatic via middleware:
```yaml
entryPoints:
  web:
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
          permanent: true
```

#### Middlewares Available
- `secure-headers` - HSTS, CSP, X-Frame-Options, etc.
- `redirect-https` - HTTP → HTTPS redirect
- `rate-limit` - Request rate limiting (100 avg, 200 burst)
- `compress` - Response compression

#### IngressRoute Example
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`grafana.aws.wiktorkowalski.pl`)
      kind: Rule
      services:
        - name: grafana
          port: 80
      middlewares:
        - name: secure-headers
          namespace: traefik-system
  tls:
    certResolver: letsencrypt
```

#### Traefik Metrics
- Exposed on port 8080 (`/metrics`)
- ServiceMonitor auto-discovered by Prometheus
- Dashboard available: https://traefik.aws.wiktorkowalski.pl (with auth)

---

### Monitoring Stack Details

#### kube-prometheus-stack (pre-rendered Helm)
**Includes:**
- Prometheus Operator
- Prometheus (metrics storage and querying)
- Alertmanager (alert routing)
- node-exporter (node metrics)
- kube-state-metrics (Kubernetes object metrics)

**Prometheus Configuration:**
- 2 replicas (HA)
- 50Gi storage per replica (gp3 EBS)
- 30-day retention
- 45GB retention size
- Scrapes: Kubernetes API, kubelet, node-exporter, kube-state-metrics, Traefik, Karpenter, ArgoCD

**Alertmanager Configuration:**
- 2 replicas (HA)
- 10Gi storage per replica
- Receivers: Slack, email (configure)

#### Grafana (separate from kube-prometheus-stack)
**Configuration:**
- 2 replicas (HA)
- 10Gi storage (gp3 EBS)
- Datasources: Prometheus, Loki, Tempo, Alertmanager
- Dashboards by ID (auto-imported from Grafana.com):
  - 7249: Kubernetes Cluster Monitoring
  - 1860: Node Exporter Full
  - 4475: Traefik Dashboard
  - 14584: ArgoCD Dashboard
  - 13639: Loki Logs

**Access:**
- https://grafana.aws.wiktorkowalski.pl
- Admin credentials in secret: `grafana-admin-secret`

#### Loki (distributed mode)
**Architecture:**
- Gateway (2 replicas) - entry point for queries and writes
- Read (2 replicas, 50Gi storage) - handles queries
- Write (2 replicas, 50Gi storage) - handles log ingestion

**Configuration:**
- 7-day retention
- Filesystem storage (can migrate to S3 for cost savings)
- Compression enabled

#### Tempo
**Configuration:**
- 2 replicas (HA)
- 50Gi storage per replica (gp3 EBS)
- 7-day retention
- OTLP receiver enabled
- Integrates with Grafana for trace visualization

#### Promtail
**Configuration:**
- DaemonSet (runs on all nodes)
- Scrapes `/var/log/pods`
- Pipeline stages for log parsing
- Sends to Loki gateway
- Tolerates all Karpenter NodePool taints

---

## GitOps Workflow

### App-of-Apps Pattern
```
Root App (k8s/argocd/apps/root-app.yaml)
  ↓
  Points to: k8s/argocd-apps/
  ↓
  ├── argocd-app.yaml (ArgoCD self-managed)
  ├── karpenter-app.yaml
  ├── traefik-app.yaml
  ├── cert-manager-app.yaml
  ├── monitoring-app.yaml (App-of-apps for monitoring)
  │   ↓
  │   Points to: k8s/monitoring/
  │   ↓
  │   ├── prometheus-stack/
  │   ├── grafana/
  │   ├── loki/
  │   ├── tempo/
  │   └── promtail/
  └── dashboard-app.yaml
```

### Deployment Flow
1. **Manual (one-time)**: `kubectl apply -k k8s/argocd/base/` - Bootstrap ArgoCD
2. **Manual (one-time)**: `kubectl apply -k k8s/argocd/apps/` - Deploy root app
3. **Automatic**: ArgoCD syncs all applications from `k8s/argocd-apps/`
4. **Continuous**: Git push → ArgoCD auto-sync → cluster updated

### Making Changes
```bash
# 1. Edit manifest
vim k8s/karpenter/base/nodepool-general.yaml

# 2. Commit and push
git add k8s/karpenter/
git commit -m "Update general NodePool instance types"
git push

# 3. ArgoCD auto-syncs (or manual sync via UI)
# Changes applied automatically within 3 minutes
```

### ArgoCD Sync Policies
- **Auto-sync**: Enabled for all applications
- **Self-heal**: Enabled (reverts manual kubectl changes)
- **Prune**: Enabled (removes resources deleted from Git)

---

## Access URLs

After complete deployment:

| Service              | URL                                        | Purpose                               |
| -------------------- | ------------------------------------------ | ------------------------------------- |
| ArgoCD               | https://argocd.aws.wiktorkowalski.pl       | GitOps management UI                  |
| Grafana              | https://grafana.aws.wiktorkowalski.pl      | Metrics/logs/traces visualization     |
| Prometheus           | https://prometheus.aws.wiktorkowalski.pl   | Metrics query interface               |
| Alertmanager         | https://alertmanager.aws.wiktorkowalski.pl | Alert management                      |
| Traefik Dashboard    | https://traefik.aws.wiktorkowalski.pl      | Traefik ingress dashboard (with auth) |
| Kubernetes Dashboard | https://dashboard.aws.wiktorkowalski.pl    | Kubernetes web UI                     |

**Default Credentials:**
- ArgoCD: `admin` / (get from secret: `argocd-initial-admin-secret`)
- Grafana: `admin` / (get from secret: `grafana-admin-secret`)

---

## Success Metrics

### Cost Savings (Expected)
| Component           | Savings | Explanation                                               |
| ------------------- | ------- | --------------------------------------------------------- |
| **Karpenter**       | 30-50%  | Better instance selection, spot optimization, bin-packing |
| **Spot Instances**  | 50-70%  | On general-purpose workloads (vs on-demand)               |
| **NLB vs ALB**      | 20-30%  | Lower per-hour cost, no LCU charges for Layer 4           |
| **ARM64 Graviton**  | 20%     | ARM64 instances cheaper than x86 equivalents              |
| **Total Estimated** | 35-55%  | Overall infrastructure cost reduction                     |

### Performance Improvements
| Metric                   | Before        | After       | Improvement            |
| ------------------------ | ------------- | ----------- | ---------------------- |
| **Node Provisioning**    | 3-5 minutes   | <60 seconds | 5x faster              |
| **Autoscaling Response** | Minutes       | Seconds     | Sub-minute pod-to-node |
| **Ingress Latency**      | 10-20ms (ALB) | <10ms (NLB) | Layer 4 vs Layer 7     |
| **TLS Handshake**        | At ALB        | At Traefik  | Flexible SSL policies  |

### Reliability Improvements
- **GitOps Coverage**: 100% (everything in Git)
- **Self-Healing**: ArgoCD auto-sync enabled
- **High Availability**: All critical components replicated (2+ replicas)
- **Spot Resilience**: Multi-AZ, multi-instance-type diversity
- **Disaster Recovery**: Git repo = complete cluster definition

---

## Validation

### Phase 1 Validation (Terraform)
```bash
# NLB exists and healthy
aws elbv2 describe-load-balancers --names eks-terraform-traefik-nlb

# Target groups created
aws elbv2 describe-target-groups | grep traefik

# Karpenter IAM roles exist
aws iam list-roles | grep Karpenter

# VPC tags correct
aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=eks-terraform"

# Route53 wildcard record
dig +short grafana.aws.wiktorkowalski.pl
```

### Phase 2 Validation (ArgoCD)
```bash
# ArgoCD pods running
kubectl get pods -n argocd

# ArgoCD UI accessible (port-forward initially)
kubectl port-forward -n argocd svc/argocd-server 8080:443
open https://localhost:8080

# Root app synced
kubectl get application -n argocd root
```

### Phase 3 Validation (Infrastructure)
```bash
# All apps synced
kubectl get applications -n argocd

# Karpenter NodePools created
kubectl get nodepools
# Expected: general-purpose, stateful, system

# Nodes provisioned
kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type

# Traefik running on all nodes
kubectl get pods -n traefik-system -o wide

# Cert-Manager issuer ready
kubectl get clusterissuer
```

### Phase 4 Validation (Monitoring)
```bash
# All monitoring pods running
kubectl get pods -n monitoring

# Prometheus targets healthy
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
open http://localhost:9090/targets

# Grafana accessible
open https://grafana.aws.wiktorkowalski.pl

# Loki receiving logs
kubectl port-forward -n monitoring svc/loki-gateway 3100:3100
curl http://localhost:3100/ready

# Tempo ready
kubectl port-forward -n monitoring svc/tempo 3100:3100
curl http://localhost:3100/ready
```

### Phase 5 Validation (Dashboard)
```bash
# Dashboard accessible
open https://dashboard.aws.wiktorkowalski.pl

# Get token for login
kubectl -n kubernetes-dashboard create token admin-user
```

### Phase 6 Validation (Migration Complete)
```bash
# All workloads on Karpenter nodes
kubectl get pods --all-namespaces -o wide | grep -v "karpenter"

# No managed node groups
kubectl get nodes -L eks.amazonaws.com/nodegroup
# Should show no nodegroup labels

# Cost Explorer in AWS Console
# Verify 30-50% cost reduction month-over-month
```

---

## Rollback Procedures

**Fresh Deployment Rollback** - Since this is a greenfield deployment, rollback is simpler:

### Complete Rollback (Destroy Everything)
```bash
# If something goes wrong during deployment, simply destroy:
cd /path/to/eks-terraform
just destroy  # Destroys all Terraform resources in reverse order
```

### Partial Rollback (Keep Cluster, Remove GitOps Components)

**Rollback ArgoCD and All Apps:**
```bash
# Delete all ArgoCD-managed apps
kubectl delete applications --all -n argocd

# Delete ArgoCD itself
kubectl delete namespace argocd

# Cleanup k8s manifests from Git (optional)
rm -rf k8s/
git commit -am "Rollback: remove all k8s manifests"
git push
```

**Rollback to Managed Nodes (Remove Karpenter):**
```bash
# 1. Scale up bootstrap node to handle workloads
# Edit infra/eks/eks.tf
eks_managed_node_groups = {
  bootstrap = {
    desired_size = 2  # Scale up
    max_size     = 3
    # ... rest unchanged
  }
}

# 2. Apply change
just apply

# 3. Drain Karpenter nodes
kubectl get nodes -l karpenter.sh/nodepool -o name | \
  xargs -I {} kubectl drain {} --ignore-daemonsets --delete-emptydir-data

# 4. Delete Karpenter NodePools
kubectl delete nodepools --all

# 5. Disable Karpenter in Terraform (optional)
# Edit infra/addons.tf: enable_karpenter = false
just apply
```

---

## Technology Stack Summary

### Core Infrastructure
- **Terraform**: v5.55.0 - Infrastructure as Code
- **Amazon EKS**: v1.30 - Kubernetes control plane
- **Karpenter**: Latest via EKS Blueprints - Node autoscaling
- **AWS VPC**: Custom VPC (10.0.0.0/16) across 3 AZs
- **fck-nat**: Cost-effective NAT alternative

### Networking & Ingress
- **Network Load Balancer (NLB)**: Layer 4 load balancing
- **Traefik v3.0**: Advanced ingress controller (DaemonSet)
- **Cert-Manager**: SSL certificate automation (Let's Encrypt)

### Monitoring & Observability
- **Prometheus**: Metrics collection and querying
- **Grafana**: Unified visualization (metrics, logs, traces)
- **Loki**: Log aggregation and analysis
- **Tempo**: Distributed tracing
- **Promtail**: Log collection (DaemonSet)
- **Alertmanager**: Alert routing and management
- **node-exporter**: Node metrics
- **kube-state-metrics**: Kubernetes object metrics

### GitOps & Deployment
- **ArgoCD**: Continuous deployment and GitOps
- **Kustomize**: Configuration management
- **Helm**: Chart rendering (for kube-prometheus-stack)
- **Git**: Source of truth for all configuration

---

## Additional Resources

### AWS Documentation
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Karpenter Documentation](https://karpenter.sh/)
- [NLB User Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)

### Community Resources
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)

### Monitoring and Observability
- [Grafana Loki Documentation](https://grafana.com/docs/loki/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)

---

## Next Steps

1. **Review this plan** - Ensure it matches your requirements
2. **Prepare Git repository** - Create `k8s/` directory structure
3. **Start Phase 1** - Apply Terraform changes (`just apply`)
4. **Bootstrap ArgoCD** - Manual `kubectl apply -k k8s/argocd/base/`
5. **Watch GitOps magic** - ArgoCD deploys everything else automatically
6. **Monitor and validate** - Check each phase's validation criteria
7. **Celebrate** - 35-55% cost savings achieved!

**Questions or Issues**: Check official documentation links above or review validation commands for each phase.
