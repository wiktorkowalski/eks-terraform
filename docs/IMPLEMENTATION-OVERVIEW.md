# EKS GitOps Implementation Overview

**Goal**: Production-ready EKS cluster with full GitOps, cost-optimized autoscaling, and complete observability

**Cost Savings**: 35-55% reduction in infrastructure costs
**Timeline**: 2-3 weeks for full implementation

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
│  ├── external-dns/ (Route53)                              │
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
- **DNS**: External-DNS for automatic Route53 updates

### Key Decisions
- ✅ Kustomize manifests in Git, deployed via ArgoCD
- ✅ Traefik DaemonSet on all nodes (NodePort 30080/30443)
- ✅ ArgoCD self-managed (bootstrap via `kubectl apply`)
- ✅ Full migration from EKS Blueprints to ArgoCD
- ✅ Native Karpenter node registration (no Lambda)
- ✅ Remove AWS Load Balancer Controller after Traefik stable
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
    │   ├── external-dns-app.yaml
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
    ├── external-dns/
    │   └── base/
    │       ├── namespace.yaml
    │       ├── deployment.yaml      # External-DNS for Route53
    │       ├── rbac.yaml
    │       ├── configmap.yaml
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

### Phase 1: Terraform Infrastructure

**Objective**: Enable Karpenter, create NLB, prepare for ArgoCD migration

**Terraform Changes:**

1. **`infra/addons.tf`** - Update EKS Blueprints:
   - Enable Karpenter with ECR auth
   - **Disable**: `enable_kube_prometheus_stack = false`
   - **Disable**: `enable_argocd = false`
   - **Disable**: `enable_aws_load_balancer_controller = false`
   - Keep: `enable_cert_manager = true` (temporarily, will migrate later)
   - Keep: `enable_external_dns = true` (temporarily, will migrate later)
   - Keep: `enable_metrics_server = true`

2. **`infra/eks/eks.tf`** - Karpenter support:
   - Add security group rules (port 8443)
   - Add node security group tags for Karpenter discovery
   - Tag existing managed node groups (will remove later)

3. **`infra/eks/nlb.tf`** (NEW FILE):
   - Create NLB in public subnets
   - Create target groups (30080 HTTP, 30443 HTTPS)
   - Create listeners (80, 443)
   - Health checks pointing to Traefik `/ping` endpoint

4. **`infra/vpc/vpc.tf`** - Add Karpenter discovery tags:
   - Public subnets: `karpenter.sh/discovery = local.cluster_name`
   - Private subnets: `karpenter.sh/discovery = local.cluster_name`

5. **`infra/route53/route53.tf`** - Wildcard DNS:
   - Add A record: `*.aws.wiktorkowalski.pl` → NLB alias

**Apply:**
```bash
just apply  # Runs terraform across all modules
```

**Deliverables:**
- ✅ Karpenter enabled via EKS Blueprints
- ✅ NLB created with target groups
- ✅ VPC subnets tagged for Karpenter discovery
- ✅ Route53 wildcard record pointing to NLB
- ✅ EKS Blueprints ArgoCD/monitoring disabled

---

### Phase 2: ArgoCD Bootstrap

**Objective**: Deploy ArgoCD manually, enable self-management

**Steps:**

1. **Create ArgoCD manifests in Git**:
   - `k8s/argocd/base/` - ArgoCD installation
   - `k8s/argocd/apps/` - Root app-of-apps

2. **Bootstrap ArgoCD** (one-time manual operation):
   ```bash
   kubectl apply -k k8s/argocd/base/
   ```

3. **Wait for ArgoCD ready**:
   ```bash
   kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
   ```

4. **Get admin password**:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath="{.data.password}" | base64 -d
   ```

5. **Deploy root app** (enables GitOps for everything):
   ```bash
   kubectl apply -k k8s/argocd/apps/
   ```

6. **Verify ArgoCD manages itself**:
   - Check `k8s/argocd-apps/argocd-app.yaml` is synced
   - ArgoCD now watches Git repo for all Application definitions

**Deliverables:**
- ✅ ArgoCD running in cluster
- ✅ ArgoCD UI accessible (port-forward for now, ingress in Phase 3)
- ✅ Root app-of-apps deployed
- ✅ ArgoCD self-management enabled
- ✅ All applications defined in `k8s/argocd-apps/` auto-deploy

---

### Phase 3: Infrastructure Components (via ArgoCD)

**Objective**: Deploy Karpenter, Traefik, Cert-Manager, External-DNS via GitOps

**What ArgoCD Deploys** (automatically from `k8s/argocd-apps/`):

1. **Karpenter**:
   - 3 NodePools (general-purpose, stateful, system)
   - 3 EC2NodeClasses
   - Auto-provisions nodes based on workload requirements

2. **Traefik**:
   - DaemonSet on all nodes
   - NodePort service (30080, 30443)
   - Middlewares (secure headers, rate limit, HTTPS redirect)
   - IngressRoutes for services

3. **Cert-Manager**:
   - CRDs and components
   - ClusterIssuer for Let's Encrypt (DNS-01 challenge via Route53)
   - Auto-issues certificates for IngressRoutes

4. **External-DNS**:
   - Watches IngressRoutes
   - Auto-updates Route53 records

**Git Commit Triggers Deployment:**
```bash
git add k8s/karpenter/ k8s/traefik/ k8s/cert-manager/ k8s/external-dns/
git commit -m "Add infrastructure components"
git push
# ArgoCD auto-syncs and deploys
```

**Validation:**
```bash
# Check all apps synced
kubectl get applications -n argocd

# Verify Karpenter
kubectl get nodepools
kubectl get nodes -L karpenter.sh/nodepool

# Verify Traefik
kubectl get pods -n traefik-system -o wide
kubectl get svc -n traefik-system

# Test ingress
curl -I https://argocd.aws.wiktorkowalski.pl
```

**Deliverables:**
- ✅ Karpenter provisioning nodes
- ✅ Traefik DaemonSet handling ingress
- ✅ Cert-Manager issuing TLS certificates
- ✅ External-DNS updating Route53
- ✅ All services accessible via HTTPS

---

### Phase 4: Monitoring Stack (via ArgoCD)

**Objective**: Deploy full observability stack via GitOps

**What ArgoCD Deploys:**

1. **kube-prometheus-stack** (pre-rendered from Helm):
   - Prometheus Operator
   - Prometheus (2 replicas, 50Gi storage, 30-day retention)
   - Alertmanager (2 replicas, 10Gi storage)
   - node-exporter (DaemonSet)
   - kube-state-metrics
   - **Note**: Grafana disabled (deployed separately)

2. **Grafana**:
   - 2 replicas, 10Gi storage
   - Datasources: Prometheus, Loki, Tempo, Alertmanager
   - Pre-configured dashboards (by ID from Grafana.com):
     - Kubernetes Cluster (7249)
     - Node Exporter Full (1860)
     - Traefik (4475)
     - ArgoCD (14584)
     - Loki Logs (13639)

3. **Loki** (distributed mode):
   - Gateway (2 replicas)
   - Read (2 replicas, 50Gi storage)
   - Write (2 replicas, 50Gi storage)
   - 7-day retention, filesystem storage

4. **Tempo**:
   - 2 replicas, 50Gi storage
   - 7-day retention
   - OTLP receiver for traces

5. **Promtail**:
   - DaemonSet on all nodes
   - Scrapes `/var/log/pods`
   - Sends to Loki gateway

**Component Placement:**
- All monitoring components use `nodeSelector: workload-type: system`
- Ensures stable, on-demand nodes

**Rendering Helm to Kustomize:**
```bash
# One-time: render kube-prometheus-stack Helm chart to YAML
helm template prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring-values.yaml \
  > k8s/monitoring/prometheus-stack/base/install.yaml

# Commit rendered YAML to Git
git add k8s/monitoring/
git commit -m "Add monitoring stack (pre-rendered from Helm)"
git push
```

**Deliverables:**
- ✅ Prometheus scraping all targets
- ✅ Grafana with datasources and dashboards
- ✅ Loki ingesting logs
- ✅ Tempo receiving traces
- ✅ Promtail collecting logs from all pods
- ✅ All accessible via IngressRoutes:
  - https://grafana.aws.wiktorkowalski.pl
  - https://prometheus.aws.wiktorkowalski.pl
  - https://alertmanager.aws.wiktorkowalski.pl

---

### Phase 5: Kubernetes Dashboard (via ArgoCD)

**Objective**: Deploy web UI for cluster management

**What ArgoCD Deploys:**
- Kubernetes Dashboard
- IngressRoute for HTTPS access

**Access:**
- https://dashboard.aws.wiktorkowalski.pl

**Deliverables:**
- ✅ Dashboard accessible via HTTPS
- ✅ Token-based authentication

---

### Phase 6: Migration & Cleanup

**Objective**: Complete migration to Karpenter, remove old components

**Migration Steps:**

1. **Scale down EKS managed node groups**:
   ```terraform
   # In infra/eks/eks.tf
   eks_managed_node_groups = {
     main = {
       desired_size = 0  # Scale to 0
       # ... rest unchanged
     }
     spot = {
       desired_size = 0  # Scale to 0
       # ... rest unchanged
     }
   }
   ```
   ```bash
   just apply
   ```

2. **Monitor workload migration**:
   - Karpenter provisions new nodes
   - Pods reschedule to Karpenter nodes
   - Verify all pods running

3. **After 1 week of stability, remove managed node groups**:
   ```terraform
   # In infra/eks/eks.tf
   # Comment out or delete:
   # eks_managed_node_groups = { ... }
   ```
   ```bash
   just apply
   ```

4. **Migrate Cert-Manager and External-DNS to ArgoCD**:
   ```terraform
   # In infra/addons.tf
   enable_cert_manager = false
   enable_external_dns = false
   ```
   ```bash
   just apply
   ```
   - ArgoCD already managing these via Kustomize

5. **Verify cleanup**:
   ```bash
   # No old resources remaining
   kubectl get pods -n kube-prometheus-stack  # Should be empty/not exist
   kubectl get deployment -n kube-system aws-load-balancer-controller  # Should not exist
   ```

**Deliverables:**
- ✅ 100% workloads on Karpenter nodes
- ✅ EKS managed node groups removed
- ✅ All infrastructure managed via ArgoCD
- ✅ Cost savings realized

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
  ├── external-dns-app.yaml
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

| Service | URL | Purpose |
|---------|-----|---------|
| ArgoCD | https://argocd.aws.wiktorkowalski.pl | GitOps management UI |
| Grafana | https://grafana.aws.wiktorkowalski.pl | Metrics/logs/traces visualization |
| Prometheus | https://prometheus.aws.wiktorkowalski.pl | Metrics query interface |
| Alertmanager | https://alertmanager.aws.wiktorkowalski.pl | Alert management |
| Traefik Dashboard | https://traefik.aws.wiktorkowalski.pl | Traefik ingress dashboard (with auth) |
| Kubernetes Dashboard | https://dashboard.aws.wiktorkowalski.pl | Kubernetes web UI |

**Default Credentials:**
- ArgoCD: `admin` / (get from secret: `argocd-initial-admin-secret`)
- Grafana: `admin` / (get from secret: `grafana-admin-secret`)

---

## Success Metrics

### Cost Savings (Expected)
| Component | Savings | Explanation |
|-----------|---------|-------------|
| **Karpenter** | 30-50% | Better instance selection, spot optimization, bin-packing |
| **Spot Instances** | 50-70% | On general-purpose workloads (vs on-demand) |
| **NLB vs ALB** | 20-30% | Lower per-hour cost, no LCU charges for Layer 4 |
| **ARM64 Graviton** | 20% | ARM64 instances cheaper than x86 equivalents |
| **Total Estimated** | 35-55% | Overall infrastructure cost reduction |

### Performance Improvements
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Node Provisioning** | 3-5 minutes | <60 seconds | 5x faster |
| **Autoscaling Response** | Minutes | Seconds | Sub-minute pod-to-node |
| **Ingress Latency** | 10-20ms (ALB) | <10ms (NLB) | Layer 4 vs Layer 7 |
| **TLS Handshake** | At ALB | At Traefik | Flexible SSL policies |

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

# External-DNS running
kubectl get pods -n external-dns
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

### Rollback Phase 2 (ArgoCD)
```bash
# Delete ArgoCD
kubectl delete namespace argocd

# Re-enable in Terraform
# Edit infra/addons.tf: enable_argocd = true
just apply

# Cleanup argocd-apps
rm -rf k8s/argocd-apps/
git commit -am "Rollback: remove ArgoCD apps"
```

### Rollback Phase 3 (Karpenter)
```bash
# Scale up managed node groups
# Edit infra/eks/eks.tf: desired_size = 2
just apply

# Drain Karpenter nodes
kubectl get nodes -l karpenter.sh/nodepool -o name | \
  xargs -I {} kubectl drain {} --ignore-daemonsets --delete-emptydir-data

# Delete Karpenter NodePools
kubectl delete nodepools --all

# Disable Karpenter in Terraform
# Edit infra/addons.tf: enable_karpenter = false
just apply
```

### Rollback Phase 3 (Traefik)
```bash
# Update ingresses to use ALB
kubectl get ingress --all-namespaces -o json | \
  jq '.items[] | select(.spec.ingressClassName=="traefik")' | \
  kubectl patch -f - -p '{"spec":{"ingressClassName":"alb"}}'

# Delete Traefik
kubectl delete namespace traefik-system

# Re-enable ALB controller
# Edit infra/addons.tf: enable_aws_load_balancer_controller = true
just apply

# Destroy NLB
# Comment out infra/eks/nlb.tf resources
just apply
```

### Rollback Phase 4 (Monitoring)
```bash
# Delete monitoring namespace
kubectl delete namespace monitoring

# Re-enable EKS Blueprints monitoring
# Edit infra/addons.tf: enable_kube_prometheus_stack = true
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
- **External-DNS**: Automated Route53 DNS management
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
