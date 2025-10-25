# Monitoring Stack Setup

The monitoring stack consists of multiple components that should be rendered from Helm charts and then customized via Kustomize.

## Components

1. **prometheus-stack**: Prometheus Operator, Prometheus, Alertmanager, node-exporter, kube-state-metrics
2. **grafana**: Visualization and dashboards
3. **loki**: Log aggregation (distributed mode)
4. **tempo**: Distributed tracing
5. **promtail**: Log collection DaemonSet

## Setup Steps

### 1. Prometheus Stack

Render the kube-prometheus-stack Helm chart to YAML:

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create values file
cat > prometheus-values.yaml <<EOF
prometheus:
  prometheusSpec:
    replicas: 2
    retention: 30d
    retentionSize: "45GB"
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
    nodeSelector:
      workload-type: system
    tolerations:
      - key: workload-type
        value: system
        effect: NoSchedule

alertmanager:
  alertmanagerSpec:
    replicas: 2
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    nodeSelector:
      workload-type: system
    tolerations:
      - key: workload-type
        value: system
        effect: NoSchedule

grafana:
  enabled: false  # We deploy Grafana separately

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
EOF

# Render to YAML
helm template prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f prometheus-values.yaml \
  --include-crds > prometheus-stack/base/manifests.yaml
```

### 2. Grafana

```bash
# Add Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create values
cat > grafana-values.yaml <<EOF
replicas: 2

persistence:
  enabled: true
  size: 10Gi

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-operated:9090
        isDefault: true
      - name: Loki
        type: loki
        url: http://loki-gateway:3100
      - name: Tempo
        type: tempo
        url: http://tempo:3100
      - name: Alertmanager
        type: alertmanager
        url: http://alertmanager-operated:9093

adminPassword: changeme

nodeSelector:
  workload-type: system

tolerations:
  - key: workload-type
    value: system
    effect: NoSchedule
EOF

# Render
helm template grafana grafana/grafana \
  -n monitoring \
  -f grafana-values.yaml > grafana/base/manifests.yaml
```

### 3. Loki (Distributed)

```bash
# Render Loki
cat > loki-values.yaml <<EOF
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 2
  storage:
    type: filesystem

read:
  replicas: 2
  persistence:
    size: 50Gi

write:
  replicas: 2
  persistence:
    size: 50Gi

gateway:
  replicas: 2

nodeSelector:
  workload-type: system

tolerations:
  - key: workload-type
    value: system
    effect: NoSchedule
EOF

helm template loki grafana/loki-distributed \
  -n monitoring \
  -f loki-values.yaml > loki/base/manifests.yaml
```

### 4. Tempo

```bash
cat > tempo-values.yaml <<EOF
tempo:
  replicas: 2
  retention: 168h  # 7 days
  storage:
    trace:
      backend: local

persistence:
  enabled: true
  size: 50Gi

nodeSelector:
  workload-type: system

tolerations:
  - key: workload-type
    value: system
    effect: NoSchedule
EOF

helm template tempo grafana/tempo \
  -n monitoring \
  -f tempo-values.yaml > tempo/base/manifests.yaml
```

### 5. Promtail

```bash
cat > promtail-values.yaml <<EOF
config:
  clients:
    - url: http://loki-gateway:3100/loki/api/v1/push

tolerations:
  - effect: NoSchedule
    operator: Exists
  - effect: NoExecute
    operator: Exists
EOF

helm template promtail grafana/promtail \
  -n monitoring \
  -f promtail-values.yaml > promtail/base/manifests.yaml
```

## Quick Start

For rapid deployment, you can also use Helm directly via ArgoCD by modifying the Application CRDs to use Helm sources instead of Git paths.

Example:
```yaml
source:
  repoURL: https://prometheus-community.github.io/helm-charts
  chart: kube-prometheus-stack
  targetRevision: 56.0.0
  helm:
    values: |
      # Your values here
```

## After Deployment

1. Access Grafana: https://grafana.aws.wiktorkowalski.pl
2. Access Prometheus: https://prometheus.aws.wiktorkowalski.pl
3. Access Alertmanager: https://alertmanager.aws.wiktorkowalski.pl

Default Grafana credentials: admin / (check secret `grafana-admin-secret`)
