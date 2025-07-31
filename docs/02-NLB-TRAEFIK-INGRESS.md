# NLB + Traefik Ingress Implementation Guide

## Overview

This guide covers implementing Network Load Balancer (NLB) with Traefik as the ingress controller to replace the current Application Load Balancer (ALB) setup. This architecture provides better performance, TCP/UDP support, and more flexible traffic routing.

## Current State Analysis

Your current setup uses:
- AWS Load Balancer Controller for ALB
- External DNS for Route53 integration
- Cert Manager for SSL certificates
- Direct ALB to service routing

## Benefits of NLB + Traefik Architecture

1. **Performance**: NLB operates at Layer 4 with lower latency
2. **Protocol Support**: TCP, UDP, TLS termination options
3. **Cost Efficiency**: Lower per-hour costs and data processing charges
4. **Flexibility**: Advanced routing, middleware, circuit breakers
5. **Observability**: Rich metrics and tracing capabilities

## Architecture Overview

```
Internet → Route53 → NLB → Traefik (DaemonSet/Deployment) → Services → Pods
```

## Implementation Steps

### 1. Update Terraform Configuration

#### Modify addons.tf to include Traefik
```terraform
# In infra/addons.tf
module "eks_blueprints_addons" {
  # ... existing configuration ...
  
  # Keep AWS Load Balancer Controller for now (transition phase)
  enable_aws_load_balancer_controller = true
  
  # We'll deploy Traefik separately for better control
  # enable_external_dns stays for Route53 automation
  enable_external_dns = true
  external_dns_route53_zone_arns = [aws_route53_zone.aws.arn]
  
  enable_cert_manager = true
  cert_manager_route53_hosted_zone_arns = [aws_route53_zone.aws.arn]
}
```

#### Create NLB Resource
```terraform
# In infra/eks/nlb.tf (new file)
resource "aws_lb" "traefik_nlb" {
  name               = "${local.cluster_name}-traefik-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection = false
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${local.cluster_name}-traefik-nlb"
    Environment = "production"
  }
}

# Target group for HTTP (port 80)
resource "aws_lb_target_group" "traefik_http" {
  name     = "${local.cluster_name}-traefik-http"
  port     = 30080
  protocol = "TCP"
  vpc_id   = data.aws_vpc.vpc.id
  
  target_type = "instance"
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/ping"
    port                = "30080"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.cluster_name}-traefik-http"
  }
}

# Target group for HTTPS (port 443)
resource "aws_lb_target_group" "traefik_https" {
  name     = "${local.cluster_name}-traefik-https"
  port     = 30443
  protocol = "TCP"
  vpc_id   = data.aws_vpc.vpc.id
  
  target_type = "instance"
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/ping"
    port                = "30080"  # Health check on HTTP port
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.cluster_name}-traefik-https"
  }
}

# Listener for HTTP
resource "aws_lb_listener" "traefik_http" {
  load_balancer_arn = aws_lb.traefik_nlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik_http.arn
  }
}

# Listener for HTTPS
resource "aws_lb_listener" "traefik_https" {
  load_balancer_arn = aws_lb.traefik_nlb.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik_https.arn
  }
}

# Auto-scaling group attachment (will be created by Karpenter or managed node groups)
resource "aws_autoscaling_attachment" "traefik_http" {
  for_each = module.eks.eks_managed_node_groups
  
  autoscaling_group_name = each.value.asg_name
  lb_target_group_arn    = aws_lb_target_group.traefik_http.arn
}

resource "aws_autoscaling_attachment" "traefik_https" {
  for_each = module.eks.eks_managed_node_groups
  
  autoscaling_group_name = each.value.asg_name
  lb_target_group_arn    = aws_lb_target_group.traefik_https.arn
}
```

### 2. Deploy Traefik with Kustomize

#### Create Traefik Directory Structure
```bash
mkdir -p k8s/traefik/base
mkdir -p k8s/traefik/overlays/production
```

#### Base Traefik Configuration
```yaml
# k8s/traefik/base/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: traefik-system
---
# k8s/traefik/base/rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik
  namespace: traefik-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traefik
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints", "secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["extensions", "networking.k8s.io"]
    resources: ["ingresses", "ingressclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["extensions", "networking.k8s.io"]
    resources: ["ingresses/status"]
    verbs: ["update"]
  - apiGroups: ["traefik.containo.us"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traefik
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik
subjects:
  - kind: ServiceAccount
    name: traefik
    namespace: traefik-system
```

```yaml
# k8s/traefik/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-config
  namespace: traefik-system
data:
  traefik.yml: |
    global:
      checkNewVersion: false
      sendAnonymousUsage: false
    
    api:
      dashboard: true
      debug: true
      insecure: true
    
    entryPoints:
      web:
        address: ":80"
        http:
          redirections:
            entrypoint:
              to: websecure
              scheme: https
              permanent: true
      websecure:
        address: ":443"
        http:
          tls:
            options: default
      traefik:
        address: ":8080"
    
    providers:
      kubernetes:
        endpoints:
          - "https://kubernetes.default.svc:443"
        ingressClass: traefik
      kubernetesIngress:
        ingressClass: traefik
        publishedService:
          enabled: true
          pathOverride: "traefik-system/traefik"
    
    certificatesResolvers:
      letsencrypt:
        acme:
          email: your-email@example.com
          storage: /data/acme.json
          httpChallenge:
            entryPoint: web
          # Alternative: DNS challenge for wildcard certs
          # dnsChallenge:
          #   provider: route53
          #   delayBeforeCheck: 60
    
    metrics:
      prometheus:
        addEntryPointsLabels: true
        addServicesLabels: true
        buckets:
          - 0.1
          - 0.3
          - 1.2
          - 5.0
    
    accessLog: {}
    
    log:
      level: INFO
```

```yaml
# k8s/traefik/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
  namespace: traefik-system
  labels:
    app: traefik
spec:
  replicas: 3
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      serviceAccountName: traefik
      containers:
        - name: traefik
          image: traefik:v3.0
          args:
            - --configFile=/config/traefik.yml
          ports:
            - name: web
              containerPort: 80
            - name: websecure
              containerPort: 443
            - name: traefik
              containerPort: 8080
          volumeMounts:
            - name: config
              mountPath: /config
            - name: data
              mountPath: /data
          livenessProbe:
            httpGet:
              path: /ping
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ping
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
      volumes:
        - name: config
          configMap:
            name: traefik-config
        - name: data
          emptyDir: {}
      nodeSelector:
        kubernetes.io/os: linux
      tolerations:
        - key: node-type
          operator: Equal
          value: general-purpose
          effect: NoSchedule
```

```yaml
# k8s/traefik/base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: traefik-system
  labels:
    app: traefik
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
      name: web
    - port: 443
      targetPort: 443
      nodePort: 30443
      name: websecure
    - port: 8080
      targetPort: 8080
      nodePort: 30808
      name: traefik
  selector:
    app: traefik
---
apiVersion: v1
kind: Service
metadata:
  name: traefik-dashboard
  namespace: traefik-system
  labels:
    app: traefik
spec:
  type: ClusterIP
  ports:
    - port: 8080
      targetPort: 8080
      name: traefik
  selector:
    app: traefik
```

```yaml
# k8s/traefik/base/ingressclass.yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: traefik
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: traefik.io/ingress-controller
```

```yaml
# k8s/traefik/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - rbac.yaml
  - configmap.yaml
  - deployment.yaml
  - service.yaml
  - ingressclass.yaml

commonLabels:
  app.kubernetes.io/name: traefik
  app.kubernetes.io/instance: traefik
  app.kubernetes.io/version: v3.0
  app.kubernetes.io/component: ingress-controller
```

### 3. Production Overlay Configuration

```yaml
# k8s/traefik/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: traefik-system

resources:
  - ../../base

patchesStrategicMerge:
  - deployment-patch.yaml
  - configmap-patch.yaml

replicas:
  - name: traefik
    count: 3
```

```yaml
# k8s/traefik/overlays/production/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
spec:
  template:
    spec:
      containers:
        - name: traefik
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          env:
            - name: AWS_REGION
              value: "eu-west-1"
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - traefik
                topologyKey: kubernetes.io/hostname
```

### 4. Dashboard and Monitoring Integration

```yaml
# k8s/traefik/overlays/production/dashboard-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: traefik-dashboard
  namespace: traefik-system
  annotations:
    traefik.ingress.kubernetes.io/router.rule: Host(`traefik.yourdomain.com`)
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-auth@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
    - host: traefik.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: traefik-dashboard
                port:
                  number: 8080
  tls:
    - hosts:
        - traefik.yourdomain.com
      secretName: traefik-dashboard-tls
```

```yaml
# k8s/traefik/overlays/production/middleware.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: auth
  namespace: traefik-system
spec:
  basicAuth:
    secret: traefik-auth
---
apiVersion: v1
kind: Secret
metadata:
  name: traefik-auth
  namespace: traefik-system
type: Opaque
data:
  # Generate with: htpasswd -nb admin password | base64
  users: YWRtaW46JGFwcjEkSDY1dnVhOU0kMVFCQUZIWDdDVjl4L0dkdndNT0wvLgoK
```

### 5. Application Ingress Examples

```yaml
# Example: Grafana Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: kube-prometheus-stack
  annotations:
    traefik.ingress.kubernetes.io/router.rule: Host(`grafana.yourdomain.com`)
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-secure-headers@kubernetescrd
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
                name: kube-prometheus-stack-grafana
                port:
                  number: 80
  tls:
    - hosts:
        - grafana.yourdomain.com
      secretName: grafana-tls
```

### 6. Advanced Traefik Features

#### Rate Limiting Middleware
```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: traefik-system
spec:
  rateLimit:
    burst: 100
    average: 50
    period: 1s
```

#### Circuit Breaker
```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: circuit-breaker
  namespace: traefik-system
spec:
  circuitBreaker:
    expression: LatencyAtQuantileMS(50.0) > 100
```

#### Secure Headers
```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: secure-headers
  namespace: traefik-system
spec:
  headers:
    accessControlAllowMethods:
      - GET
      - OPTIONS
      - PUT
      - POST
    accessControlMaxAge: 100
    hostsProxyHeaders:
      - "X-Forwarded-Host"
    sslRedirect: true
    stsSeconds: 63072000
    stsIncludeSubdomains: true
    stsPreload: true
    forceSTSHeader: true
    frameDeny: true
    contentTypeNosniff: true
    browserXssFilter: true
    referrerPolicy: "same-origin"
```

### 7. Monitoring and Observability

#### ServiceMonitor for Prometheus
```yaml
# k8s/traefik/overlays/production/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: traefik
  namespace: traefik-system
  labels:
    app: traefik
spec:
  selector:
    matchLabels:
      app: traefik
  endpoints:
    - port: traefik
      path: /metrics
      interval: 30s
```

#### Grafana Dashboard ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-dashboard
  namespace: kube-prometheus-stack
  labels:
    grafana_dashboard: "1"
data:
  traefik.json: |
    {
      "dashboard": {
        "id": null,
        "title": "Traefik Dashboard",
        "tags": ["traefik"],
        "style": "dark",
        "timezone": "browser",
        "panels": [
          // Dashboard JSON content here
        ]
      }
    }
```

### 8. Migration Strategy

#### Phase 1: Parallel Deployment
1. Deploy Traefik alongside existing ALB setup
2. Test with non-critical services
3. Monitor performance and reliability

#### Phase 2: Service Migration
```bash
# Migrate services one by one
kubectl patch ingress grafana-ingress -p '{"spec":{"ingressClassName":"traefik"}}'
```

#### Phase 3: DNS Cutover
```yaml
# Update Route53 records to point to NLB
# External DNS will handle this automatically
```

### 9. Performance Tuning

#### NLB Optimizations
- Enable cross-zone load balancing
- Use connection draining
- Configure appropriate health check intervals

#### Traefik Optimizations
```yaml
# In configmap
global:
  checkNewVersion: false
  sendAnonymousUsage: false

entryPoints:
  web:
    address: ":80"
    transport:
      respondingTimeouts:
        readTimeout: 60s
        writeTimeout: 60s
        idleTimeout: 180s
```

### 10. Troubleshooting

#### Check Traefik Status
```bash
kubectl get pods -n traefik-system
kubectl logs -n traefik-system deployment/traefik
```

#### Verify NLB Target Health
```bash
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

#### Debug Ingress Routing
```bash
kubectl describe ingress -n <namespace> <ingress-name>
```

### 11. Cost Optimization

1. **Right-size NLB**: Monitor connection patterns
2. **Instance Target Registration**: Use Karpenter node optimization
3. **SSL Termination**: Choose between NLB and Traefik termination
4. **Health Check Frequency**: Balance reliability vs costs

This implementation provides a robust, scalable, and cost-effective ingress solution with advanced traffic management capabilities.
