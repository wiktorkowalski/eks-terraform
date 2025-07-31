# Grafana-Prometheus-Loki Stack with Kustomize Implementation Guide

## Overview

This guide covers optimizing and extending your existing monitoring stack by deploying Grafana, Prometheus, and Loki using Kustomize with Helm charts. This approach provides better configuration management, GitOps integration, and customization capabilities.

## Current State Analysis

Your current setup includes:
- kube-prometheus-stack via EKS Blueprints (Helm-based)
- Basic Grafana configuration with Loki data source
- Prometheus for metrics collection
- Basic monitoring for cluster components

## Benefits of Kustomize + Helm Approach

1. **Configuration Management**: Version-controlled, environment-specific configs
2. **GitOps Ready**: Seamless integration with ArgoCD
3. **Customization**: Layer-based configuration without Helm value sprawl
4. **Modularity**: Independent component management
5. **Debugging**: Clear separation of concerns and easier troubleshooting

## Architecture Overview

```
ArgoCD → Kustomize → Helm Charts → Kubernetes Resources
                ↓
    [Prometheus] ← [Grafana] → [Loki]
         ↑             ↓         ↑
    [Exporters]  [Dashboards] [Promtail]
```

## Implementation Steps

### 1. Migrate from EKS Blueprints to Kustomize

#### Phase 1: Disable EKS Blueprints Monitoring
```terraform
# In infra/addons.tf - comment out or set to false
module "eks_blueprints_addons" {
  # ... existing configuration ...
  
  # Disable to use our custom Kustomize setup
  enable_kube_prometheus_stack = false
  
  # Keep other addons
  enable_aws_load_balancer_controller = true
  enable_external_dns = true
  enable_cert_manager = true
  enable_argocd = true
}
```

### 2. Directory Structure Setup

```bash
k8s/monitoring/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── common-config.yaml
├── components/
│   ├── prometheus/
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   ├── application.yaml
│   │   │   └── values.yaml
│   │   └── overlays/
│   │       └── production/
│   ├── grafana/
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   ├── application.yaml
│   │   │   └── values.yaml
│   │   └── overlays/
│   │       └── production/
│   └── loki/
│       ├── base/
│       │   ├── kustomization.yaml
│       │   ├── application.yaml
│       │   └── values.yaml
│       └── overlays/
│           └── production/
└── overlays/
    └── production/
        ├── kustomization.yaml
        ├── grafana-ingress.yaml
        ├── servicemonitors.yaml
        └── custom-dashboards/
```

### 3. Base Configuration

#### Common Base Setup
```yaml
# k8s/monitoring/base/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

```yaml
# k8s/monitoring/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

resources:
  - namespace.yaml

commonLabels:
  app.kubernetes.io/part-of: monitoring-stack
  app.kubernetes.io/managed-by: kustomize
```

### 4. Prometheus Configuration with ArgoCD

#### Prometheus ArgoCD Application
```yaml
# k8s/monitoring/components/prometheus/base/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 56.0.0
    helm:
      releaseName: prometheus
      values: |
        # Prometheus configuration
        prometheus:
          prometheusSpec:
            serviceMonitorSelectorNilUsesHelmValues: false
            podMonitorSelectorNilUsesHelmValues: false
            probeSelectorNilUsesHelmValues: false
            ruleSelectorNilUsesHelmValues: false
            
            # Storage configuration
            storageSpec:
              volumeClaimTemplate:
                spec:
                  storageClassName: gp3
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 50Gi
            
            # Retention settings
            retention: 30d
            retentionSize: 45GB
            
            # Resource configuration
            resources:
              requests:
                cpu: 500m
                memory: 2Gi
              limits:
                cpu: 2000m
                memory: 8Gi
            
            # High availability
            replicas: 2
            
            # Additional scrape configs
            additionalScrapeConfigs:
              - job_name: 'kubernetes-pods'
                kubernetes_sd_configs:
                  - role: pod
                relabel_configs:
                  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                    action: keep
                    regex: true
                  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
                    action: replace
                    target_label: __metrics_path__
                    regex: (.+)
                  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
                    action: replace
                    regex: ([^:]+)(?::\d+)?;(\d+)
                    replacement: $1:$2
                    target_label: __address__

        # Alertmanager configuration
        alertmanager:
          alertmanagerSpec:
            storage:
              volumeClaimTemplate:
                spec:
                  storageClassName: gp3
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 10Gi
            replicas: 2
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                cpu: 500m
                memory: 512Mi

        # Disable Grafana - managed separately
        grafana:
          enabled: false

        # Node Exporter
        nodeExporter:
          enabled: true

        # kube-state-metrics
        kubeStateMetrics:
          enabled: true

        # Prometheus Operator
        prometheusOperator:
          enabled: true
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 5. Grafana Configuration with ArgoCD

#### Grafana ArgoCD Application
```yaml
# k8s/monitoring/components/grafana/base/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: grafana
    targetRevision: 7.0.0
    helm:
      releaseName: grafana
      values: |
        # High availability
        replicas: 2

        # Admin credentials from secret
        admin:
          existingSecret: "grafana-admin-secret"
          userKey: username
          passwordKey: password

        # Data sources
        datasources:
          datasources.yaml:
            apiVersion: 1
            datasources:
              - name: Prometheus
                type: prometheus
                url: http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090
                access: proxy
                isDefault: true
                jsonData:
                  timeInterval: 30s
                  httpMethod: POST
              - name: Loki
                type: loki
                url: http://loki-gateway.monitoring.svc.cluster.local
                access: proxy
                jsonData:
                  maxLines: 1000
                  timeout: 60
                  httpHeaderName1: "X-Scope-OrgID"
              - name: Alertmanager
                type: alertmanager
                url: http://prometheus-kube-prometheus-alertmanager.monitoring.svc.cluster.local:9093
                access: proxy

        # Dashboard providers
        dashboardProviders:
          dashboardproviders.yaml:
            apiVersion: 1
            providers:
              - name: 'default'
                orgId: 1
                folder: ''
                type: file
                disableDeletion: false
                editable: true
                options:
                  path: /var/lib/grafana/dashboards/default
              - name: 'kubernetes'
                orgId: 1
                folder: 'Kubernetes'
                type: file
                disableDeletion: false
                editable: true
                options:
                  path: /var/lib/grafana/dashboards/kubernetes
              - name: 'applications'
                orgId: 1
                folder: 'Applications'
                type: file
                disableDeletion: false
                editable: true
                options:
                  path: /var/lib/grafana/dashboards/applications

        # Pre-configured dashboards
        dashboards:
          kubernetes:
            # Kubernetes cluster monitoring
            kubernetes-cluster:
              gnetId: 7249
              revision: 1
              datasource: Prometheus
            # Node Exporter Full
            node-exporter-full:
              gnetId: 1860
              revision: 31
              datasource: Prometheus
            # Kubernetes Workload
            kubernetes-workload:
              gnetId: 7630
              revision: 1
              datasource: Prometheus
          applications:
            # Traefik dashboard
            traefik:
              gnetId: 4475
              revision: 5
              datasource: Prometheus
            # ArgoCD dashboard
            argocd:
              gnetId: 14584
              revision: 1
              datasource: Prometheus
            # Loki dashboard
            loki-logs:
              gnetId: 13639
              revision: 2
              datasource: Loki

        # Persistence
        persistence:
          enabled: true
          type: pvc
          storageClassName: gp3
          accessModes:
            - ReadWriteOnce
          size: 10Gi

        # Resources
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi

        # Security context
        securityContext:
          runAsUser: 472
          runAsGroup: 472
          runAsNonRoot: true
          fsGroup: 472

        # Service configuration
        service:
          type: ClusterIP
          port: 80

        # Grafana configuration
        grafana.ini:
          server:
            domain: grafana.yourdomain.com
            root_url: https://grafana.yourdomain.com
            serve_from_sub_path: false
          auth:
            disable_login_form: false
          auth.anonymous:
            enabled: false
          security:
            allow_embedding: true
            cookie_secure: true
            cookie_samesite: strict
          log:
            level: info
          analytics:
            reporting_enabled: false
            check_for_updates: false
          snapshots:
            external_enabled: false
          users:
            allow_sign_up: false
            auto_assign_org: true
            auto_assign_org_role: Viewer

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 6. Loki Configuration with ArgoCD

#### Loki ArgoCD Application
```yaml
# k8s/monitoring/components/loki/base/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: loki
    targetRevision: 5.36.0
    helm:
      releaseName: loki
      values: |
        # Loki configuration
        loki:
          auth_enabled: false
          
          server:
            http_listen_port: 3100
            grpc_listen_port: 9095
          
          common:
            path_prefix: /var/loki
            storage:
              filesystem:
                chunks_directory: /var/loki/chunks
                rules_directory: /var/loki/rules
            replication_factor: 1
            ring:
              kvstore:
                store: inmemory
          
          schema_config:
            configs:
              - from: 2020-10-24
                store: boltdb-shipper
                object_store: filesystem
                schema: v11
                index:
                  prefix: index_
                  period: 24h
          
          storage_config:
            boltdb_shipper:
              active_index_directory: /var/loki/boltdb-shipper-active
              cache_location: /var/loki/boltdb-shipper-cache
              cache_ttl: 24h
              shared_store: filesystem
            filesystem:
              directory: /var/loki/chunks
          
          limits_config:
            retention_period: 168h  # 7 days
            enforce_metric_name: false
            reject_old_samples: true
            reject_old_samples_max_age: 168h
            ingestion_rate_mb: 16
            ingestion_burst_size_mb: 32
            max_label_name_length: 1024
            max_label_value_length: 4096
            max_label_names_per_series: 30

        # Deployment mode
        deploymentMode: SimpleScalable

        # Gateway
        gateway:
          enabled: true
          replicas: 2
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

        # Write component
        write:
          replicas: 2
          persistence:
            enabled: true
            storageClass: gp3
            size: 50Gi
          resources:
            requests:
              cpu: 300m
              memory: 1Gi
            limits:
              cpu: 1000m
              memory: 2Gi

        # Read component
        read:
          replicas: 2
          persistence:
            enabled: true
            storageClass: gp3
            size: 50Gi
          resources:
            requests:
              cpu: 300m
              memory: 1Gi
            limits:
              cpu: 1000m
              memory: 2Gi

        # Backend component
        backend:
          replicas: 2
          persistence:
            enabled: true
            storageClass: gp3
            size: 50Gi
          resources:
            requests:
              cpu: 300m
              memory: 1Gi
            limits:
              cpu: 1000m
              memory: 2Gi

        # Promtail for log collection
        promtail:
          enabled: true
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
          
          config:
            logLevel: info
            serverPort: 3101
            clients:
              - url: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
            
            positions:
              filename: /tmp/positions.yaml
            
            scrape_configs:
              # Kubernetes pods
              - job_name: kubernetes-pods
                kubernetes_sd_configs:
                  - role: pod
                pipeline_stages:
                  - cri: {}
                relabel_configs:
                  - source_labels: [__meta_kubernetes_pod_controller_name]
                    regex: ([0-9a-z-.]+?)(-[0-9a-f]{8,10})?
                    action: replace
                    target_label: __tmp_controller_name
                  - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name, __meta_kubernetes_pod_label_app, __tmp_controller_name, __meta_kubernetes_pod_name]
                    regex: ^;*([^;]+)(;.*)?$
                    action: replace
                    target_label: app
                  - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_instance, __meta_kubernetes_pod_label_instance]
                    regex: ^;*([^;]+)(;.*)?$
                    action: replace
                    target_label: instance
                  - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_component, __meta_kubernetes_pod_label_component]
                    regex: ^;*([^;]+)(;.*)?$
                    action: replace
                    target_label: component

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 7. Kustomize Integration

#### Base Kustomization for Monitoring Components
```yaml
# k8s/monitoring/components/prometheus/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - application.yaml

commonLabels:
  app.kubernetes.io/name: prometheus
  app.kubernetes.io/component: monitoring
```

```yaml
# k8s/monitoring/components/grafana/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - application.yaml

secretGenerator:
  - name: grafana-admin-secret
    literals:
      - username=admin
      - password=admin123  # Change this!
    type: Opaque

commonLabels:
  app.kubernetes.io/name: grafana
  app.kubernetes.io/component: monitoring
```

```yaml
# k8s/monitoring/components/loki/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - application.yaml

commonLabels:
  app.kubernetes.io/name: loki
  app.kubernetes.io/component: monitoring
```

### 8. Production Overlay

```yaml
# k8s/monitoring/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

resources:
  - ../../base
  - ../../components/prometheus/base
  - ../../components/grafana/base
  - ../../components/loki/base
  - grafana-ingress.yaml
  - servicemonitors.yaml
  - prometheus-rules.yaml

configMapGenerator:
  - name: custom-dashboards
    files:
      - custom-dashboards/application-metrics.json
      - custom-dashboards/business-kpis.json

secretGenerator:
  - name: grafana-admin-secret
    behavior: replace
    literals:
      - username=admin
      - password=your-secure-password-here
    type: Opaque
```

#### Grafana Ingress
```yaml
# k8s/monitoring/overlays/production/grafana-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    traefik.ingress.kubernetes.io/router.rule: Host(`grafana.yourdomain.com`)
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    traefik.ingress.kubernetes.io/router.middlewares: monitoring-secure-headers@kubernetescrd
    external-dns.alpha.kubernetes.io/hostname: grafana.yourdomain.com
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  rules:
    - host: grafana.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
  tls:
    - hosts:
        - grafana.yourdomain.com
      secretName: grafana-tls
```

### 9. Custom ServiceMonitors

```yaml
# k8s/monitoring/overlays/production/servicemonitors.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: traefik-metrics
  namespace: monitoring
  labels:
    app: traefik
spec:
  selector:
    matchLabels:
      app: traefik
  namespaceSelector:
    matchNames:
      - traefik-system
  endpoints:
    - port: traefik
      path: /metrics
      interval: 30s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: monitoring
  labels:
    app: argocd
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
  namespaceSelector:
    matchNames:
      - argocd
  endpoints:
    - port: metrics
      interval: 30s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: karpenter-metrics
  namespace: monitoring
  labels:
    app: karpenter
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: karpenter
  namespaceSelector:
    matchNames:
      - karpenter
  endpoints:
    - port: http-metrics
      interval: 30s
```

### 10. Custom Prometheus Rules

```yaml
# k8s/monitoring/overlays/production/prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-application-rules
  namespace: monitoring
  labels:
    app: prometheus
spec:
  groups:
    - name: application.rules
      rules:
        - alert: HighErrorRate
          expr: |
            (
              rate(traefik_service_request_duration_seconds_count{code=~"5.."}[5m])
              /
              rate(traefik_service_request_duration_seconds_count[5m])
            ) * 100 > 5
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High error rate detected for {{ $labels.service }}"
            description: "Error rate is {{ $value }}% for service {{ $labels.service }}"
        
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ $labels.pod }} is crash looping"
            description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has restarted {{ $value }} times in the last 15 minutes"
        
        - alert: NodeDiskSpaceRunningLow
          expr: |
            (
              node_filesystem_avail_bytes{mountpoint="/"}
              /
              node_filesystem_size_bytes{mountpoint="/"}
            ) * 100 < 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Node {{ $labels.instance }} disk space running low"
            description: "Node {{ $labels.instance }} has {{ $value }}% disk space remaining"
        
        - alert: KarpenterNodeProvisioningFailed
          expr: increase(karpenter_nodes_terminated_total{reason="failed"}[10m]) > 0
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "Karpenter node provisioning failures detected"
            description: "{{ $value }} node(s) failed to provision in the last 10 minutes"

    - name: loki.rules
      rules:
        - alert: LokiTooManyLogErrors
          expr: |
            (
              rate(loki_ingester_samples_received_total{job="loki"}[5m])
              -
              rate(loki_ingester_samples_received_total{job="loki"}[5m] offset 1h)
            ) / rate(loki_ingester_samples_received_total{job="loki"}[5m] offset 1h) * 100 > 50
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Loki error rate increased significantly"
            description: "Loki error rate has increased by {{ $value }}% compared to 1 hour ago"
```

### 11. Custom Dashboards

#### Application Performance Dashboard
```json
# k8s/monitoring/overlays/production/custom-dashboards/application-metrics.json
{
  "dashboard": {
    "id": null,
    "title": "Application Performance Metrics",
    "tags": ["application", "performance", "custom"],
    "timezone": "browser",
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "30s",
    "panels": [
      {
        "id": 1,
        "title": "Request Rate by Service",
        "type": "timeseries",
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 0
        },
        "targets": [
          {
            "expr": "sum(rate(traefik_service_request_duration_seconds_count[5m])) by (service)",
            "legendFormat": "{{service}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "reqps"
          }
        }
      },
      {
        "id": 2,
        "title": "Error Rate by Service",
        "type": "timeseries",
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 0
        },
        "targets": [
          {
            "expr": "sum(rate(traefik_service_request_duration_seconds_count{code=~\"5..\"}[5m])) by (service)",
            "legendFormat": "{{service}} errors"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "reqps",
            "color": {
              "mode": "palette-classic"
            }
          }
        }
      },
      {
        "id": 3,
        "title": "Response Time P95",
        "type": "timeseries",
        "gridPos": {
          "h": 8,
          "w": 24,
          "x": 0,
          "y": 8
        },
        "targets": [
          {
            "expr": "histogram_quantile(0.95, sum(rate(traefik_service_request_duration_seconds_bucket[5m])) by (service, le))",
            "legendFormat": "{{service}} P95"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "s"
          }
        }
      }
    ]
  }
}
```

### 12. Migration Strategy

#### Phase 1: Parallel Deployment (Week 1)
1. Deploy new monitoring stack alongside existing EKS Blueprints
2. Validate data collection and dashboards
3. Test alerting functionality

#### Phase 2: Data Validation (Week 2)
1. Compare metrics between old and new systems
2. Migrate custom dashboards
3. Update alert routing

#### Phase 3: Complete Migration (Week 3)
1. Disable EKS Blueprints monitoring
2. Update all references to new service names
3. Clean up old resources

#### Phase 4: Optimization (Week 4)
1. Fine-tune retention policies
2. Optimize resource allocations
3. Add custom metrics and dashboards

### 13. Troubleshooting Guide

#### Common Issues

**Prometheus Data Missing**
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check ServiceMonitor resources
kubectl get servicemonitors -n monitoring
```

**Grafana Dashboard Issues**
```bash
# Check Grafana logs
kubectl logs -n monitoring deployment/grafana

# Verify data source connectivity
kubectl exec -n monitoring deployment/grafana -- wget -qO- http://prometheus-kube-prometheus-prometheus:9090/api/v1/query?query=up
```

**Loki Log Ingestion Problems**
```bash
# Check Promtail status
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# Verify Loki ingestion
kubectl logs -n monitoring deployment/loki-gateway
```

### 14. Performance Optimization

#### Storage Optimization
- Use gp3 volumes with appropriate IOPS
- Implement retention policies
- Consider using S3 for long-term storage

#### Resource Optimization
```yaml
# Recommended resource allocations
prometheus:
  resources:
    requests: { cpu: 1000m, memory: 4Gi }
    limits: { cpu: 2000m, memory: 8Gi }

grafana:
  resources:
    requests: { cpu: 200m, memory: 512Mi }
    limits: { cpu: 500m, memory: 1Gi }

loki:
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits: { cpu: 1000m, memory: 2Gi }
```

### 15. Security Considerations

1. **Access Control**: Use RBAC for service accounts
2. **Network Policies**: Implement pod-to-pod communication restrictions
3. **Secrets Management**: Use external secret management for sensitive data
4. **TLS**: Enable TLS for all inter-component communication

### 16. Backup and Disaster Recovery

#### Prometheus Backup
```bash
# Backup Prometheus data
kubectl exec -n monitoring prometheus-kube-prometheus-prometheus-0 -- \
  tar czf - /prometheus | aws s3 cp - s3://your-backup-bucket/prometheus-$(date +%Y%m%d).tar.gz
```

#### Grafana Configuration Backup
```bash
# Export dashboards
kubectl get configmaps -n monitoring -o yaml > grafana-dashboards-backup.yaml
```

This comprehensive implementation provides a robust, scalable, and maintainable monitoring solution that integrates seamlessly with your GitOps workflow.
