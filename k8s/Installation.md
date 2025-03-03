# Kubernetes Services Deployment Guide

This guide provides instructions for deploying the included Kubernetes services to a local Kubernetes cluster running on Docker Desktop. It includes steps to fix path discrepancies and adapt AWS-specific configurations for local use.

## Prerequisites

- Docker Desktop installed with Kubernetes enabled
- kubectl CLI tool installed
- kustomize CLI tool installed (optional, as kubectl has built-in kustomize support)

## Overview of Services

This repository contains the following Kubernetes services:

- **ArgoCD**: Continuous Delivery tool
- **Kubernetes Dashboard**: Web UI for managing Kubernetes resources
- **Metrics Server**: Resource metrics collection
- **Monitoring Stack**:
  - **Grafana**: Visualization and dashboards
  - **Loki**: Log aggregation
  - **Tempo**: Distributed tracing
  - **Mimir**: Metrics storage (Prometheus compatible)

## Deployment Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/wiktorkowalski/eks-terraform.git
cd eks-terraform
```

### 2. Deploy ArgoCD

ArgoCD is the foundation for deploying the other services.

```bash
# Create the ArgoCD namespace
kubectl apply -f k8s/argocd/namespace.yml

# Deploy ArgoCD
kubectl apply -k k8s/argocd/
```

Wait for ArgoCD to be ready:

```bash
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

Get the ArgoCD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access ArgoCD UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

Then open http://localhost:8080 in your browser and log in with username `admin` and the password retrieved above.

### 3. Deploy Kubernetes Dashboard

```bash
kubectl apply -k k8s/dashboard/
```

Access the Dashboard:

```bash
kubectl port-forward svc/kubernetes-dashboard -n kubernetes-dashboard 8081:9090
```

Then open http://localhost:8081 in your browser.

To get an authentication token for the dashboard:

```bash
kubectl -n kubernetes-dashboard create token dashboard-admin
```

### 4. Deploy Metrics Server

```bash
kubectl apply -k k8s/metrics-server/
```

Verify metrics server is working:

```bash
kubectl top nodes
kubectl top pods --all-namespaces
```

### 5. Deploy Monitoring Stack

#### 5.1 Create Monitoring Namespace

```bash
kubectl apply -f k8s/loki/namespace.yml
```

#### 5.2 Deploy Loki (Log Aggregation)

```bash
kubectl apply -k k8s/loki/
```

#### 5.3 Deploy Tempo (Distributed Tracing)

```bash
kubectl apply -k k8s/tempo/
```

#### 5.4 Deploy Mimir (Metrics Storage)

```bash
kubectl apply -k k8s/mimir/
```

#### 5.5 Deploy Grafana (Visualization)

```bash
kubectl apply -k k8s/grafana/
```

Access Grafana:

```bash
kubectl port-forward svc/grafana -n monitoring 3000:3000
```

Then open http://localhost:3000 in your browser. The default login is:
- Username: admin
- Password: admin

### 6. Configure Grafana Data Sources

After logging into Grafana, you'll need to configure data sources to connect to Loki, Tempo, and Mimir:

1. Go to Configuration > Data Sources
2. Add Loki data source:
   - Name: Loki
   - URL: http://loki-gateway.monitoring.svc:80
   - Click "Save & Test"

3. Add Tempo data source:
   - Name: Tempo
   - URL: http://tempo-query-frontend.monitoring.svc:3100
   - Click "Save & Test"

4. Add Mimir data source:
   - Name: Mimir
   - URL: http://mimir-nginx.monitoring.svc:80/prometheus
   - Click "Save & Test"

### 7. Making Services Work Properly

#### 7.1 Accessing the Kubernetes Dashboard

The Kubernetes Dashboard is configured to allow insecure access and skip login. However, for security reasons, you should use the token authentication method:

1. Get a token for the dashboard-admin service account:
   ```bash
   kubectl -n kubernetes-dashboard create token dashboard-admin
   ```

2. Access the dashboard using port-forward:
   ```bash
   kubectl port-forward svc/kubernetes-dashboard -n kubernetes-dashboard 8081:9090
   ```

3. Open http://localhost:8081 in your browser and use the token to log in.

#### 7.2 Setting Up Log Collection with Loki

To ensure logs are being collected properly by Loki:

1. Verify Loki is running:
   ```bash
   kubectl get pods -n monitoring | grep loki
   ```

2. Loki should automatically collect logs from all containers in the cluster. To verify:
   - Access Grafana (http://localhost:3000)
   - Go to Explore
   - Select Loki as the data source
   - Try a simple query like `{app="loki-gateway"}` or `{namespace="monitoring"}`
   - You should see logs appearing

3. If logs are not appearing, check the Loki components:
   ```bash
   kubectl logs -n monitoring deployment/loki-gateway
   ```

#### 7.3 Setting Up Metrics Collection with Mimir

To ensure metrics are being collected properly:

1. Verify Mimir is running:
   ```bash
   kubectl get pods -n monitoring | grep mimir
   ```

2. Access Mimir through Grafana:
   - Go to Explore
   - Select Mimir as the data source
   - Try a simple query like `up` to see which targets are being scraped
   - You should see metrics from various services

3. If metrics are not appearing, check the Mimir components:
   ```bash
   kubectl logs -n monitoring deployment/mimir-nginx
   ```

#### 7.4 Setting Up Distributed Tracing with Tempo

To ensure traces are being collected properly:

1. Verify Tempo is running:
   ```bash
   kubectl get pods -n monitoring | grep tempo
   ```

2. Tempo requires instrumented applications to send traces. For testing, you can deploy a sample application:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/grafana/tempo/main/example/docker-compose/synthetic-load-generator/k8s/deployment.yaml
   ```

3. Access Tempo through Grafana:
   - Go to Explore
   - Select Tempo as the data source
   - Use the "Search" tab to find traces

## Accessing Services

### Method 1: Using kubectl port-forward

This is the simplest method for accessing services on a local Kubernetes cluster:

### ArgoCD
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
```
Access at: http://localhost:8080

### Kubernetes Dashboard
```bash
kubectl port-forward svc/kubernetes-dashboard -n kubernetes-dashboard 8081:9090
```
Access at: http://localhost:8081

### Grafana
```bash
kubectl port-forward svc/grafana -n monitoring 3000:3000
```
Access at: http://localhost:3000

### Loki
```bash
kubectl port-forward svc/loki-gateway -n monitoring 3100:80
```
Access at: http://localhost:3100

### Tempo
```bash
kubectl port-forward svc/tempo-query-frontend -n monitoring 3200:3100
```
Access at: http://localhost:3200

### Mimir
```bash
kubectl port-forward svc/mimir-nginx -n monitoring 9090:80
```
Access at: http://localhost:9090

### Method 2: Using kubectl proxy

An alternative to port-forwarding is to use `kubectl proxy`, which creates a proxy server between your local machine and the Kubernetes API server. This allows you to access services through the Kubernetes API paths.

1. Start the proxy server:
   ```bash
   kubectl proxy
   ```

2. Access services through the proxy. The URL format is:
   ```
   http://localhost:8001/api/v1/namespaces/<namespace>/services/<service-name>:<service-port>/proxy/
   ```

Examples:

- Kubernetes Dashboard:
  ```
  http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/kubernetes-dashboard:9090/proxy/
  ```

- Grafana:
  ```
  http://localhost:8001/api/v1/namespaces/monitoring/services/grafana:3000/proxy/
  ```

- ArgoCD:
  ```
  http://localhost:8001/api/v1/namespaces/argocd/services/argocd-server:80/proxy/
  ```

- Loki (through gateway):
  ```
  http://localhost:8001/api/v1/namespaces/monitoring/services/loki-gateway:80/proxy/
  ```

- Tempo:
  ```
  http://localhost:8001/api/v1/namespaces/monitoring/services/tempo-query-frontend:3100/proxy/
  ```

- Mimir:
  ```
  http://localhost:8001/api/v1/namespaces/monitoring/services/mimir-nginx:80/proxy/prometheus/
  ```

The advantage of this method is that you only need to run one command (`kubectl proxy`) to access all services, rather than running multiple port-forward commands.

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -A
```

### View Pod Logs
```bash
kubectl logs -n <namespace> <pod-name>
```

### Describe Resources
```bash
kubectl describe pod -n <namespace> <pod-name>
```

## Fixing Path Discrepancies

Before deploying the services, you need to fix the path discrepancies in the application.yml files. The following files need to be updated:

1. **Metrics Server**: Update `k8s/metrics-server/application.yml`
   ```bash
   sed -i 's|path: k8s/addons/metrics-server/|path: k8s/metrics-server/|' k8s/metrics-server/application.yml
   ```

2. **Loki**: Update `k8s/loki/application.yml`
   ```bash
   sed -i 's|path: k8s/addons/loki/|path: k8s/loki/|' k8s/loki/application.yml
   ```

3. **Grafana**: Update `k8s/grafana/application.yml`
   ```bash
   sed -i 's|path: k8s/addons/grafana/|path: k8s/grafana/|' k8s/grafana/application.yml
   ```

4. **Tempo**: Update `k8s/tempo/application.yml`
   ```bash
   sed -i 's|path: k8s/addons/tempo/|path: k8s/tempo/|' k8s/tempo/application.yml
   ```

5. **Mimir**: Update `k8s/mimir/application.yml`
   ```bash
   sed -i 's|path: k8s/addons/mimir/|path: k8s/mimir/|' k8s/mimir/application.yml
   ```

## Adapting Ingress Resources for Local Use

The ingress resources in this repository are configured for AWS EKS with the AWS Load Balancer Controller. For local deployment on Docker Desktop Kubernetes, you have two options:

### Option 1: Use kubectl port-forward (Recommended for local development)

This is the simplest approach and is already covered in the "Accessing Services" section above.

### Option 2: Deploy NGINX Ingress Controller

If you want to use ingress resources locally:

1. Install NGINX Ingress Controller:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
   ```

2. Create local ingress resources for each service. For example, for Grafana:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: grafana-ingress
     namespace: monitoring
     annotations:
       kubernetes.io/ingress.class: nginx
   spec:
     rules:
     - host: grafana.local
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: grafana
               port:
                 number: 3000
   ```

3. Add entries to your hosts file (`/etc/hosts` on macOS/Linux or `C:\Windows\System32\drivers\etc\hosts` on Windows):
   ```
   127.0.0.1 grafana.local
   127.0.0.1 argocd.local
   127.0.0.1 dashboard.local
   127.0.0.1 loki.local
   127.0.0.1 tempo.local
   127.0.0.1 mimir.local
   ```

## Notes for Local Deployment

1. **AWS-specific configurations**: The original configurations were designed for AWS EKS with AWS Load Balancer Controller. For local deployment, we're using port-forwarding or NGINX Ingress Controller instead.

2. **Storage**: The monitoring stack (Loki, Tempo, Mimir) is configured to use ephemeral storage. For production use, you would want to configure persistent storage.

3. **Resource Limits**: You may need to adjust resource requests and limits based on your local machine's capabilities. Docker Desktop has limited resources compared to a cloud environment.

4. **ArgoCD Applications**: The ArgoCD applications are configured to point to paths that may not exist in the repository. The instructions above include steps to modify the application.yml files to point to the correct paths.

5. **DNS and TLS**: The original configurations use external-dns and AWS Certificate Manager for DNS and TLS. These won't work locally, so we're using local hostnames and HTTP instead.
