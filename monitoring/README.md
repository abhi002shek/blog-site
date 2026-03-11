# Monitoring Stack Installation Guide

This directory contains configuration for Prometheus and Grafana monitoring stack.

## Quick Install

### 1. Install Prometheus Stack (includes Grafana)

```bash
# Add Prometheus community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack (Prometheus + Grafana + AlertManager)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi
```

### 2. Access Grafana Dashboard

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open browser: http://localhost:3000
# Username: admin
# Password: admin123
```

### 3. Access Prometheus UI

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open browser: http://localhost:9090
```

## Pre-configured Dashboards

The stack includes these dashboards out of the box:
- Kubernetes Cluster Monitoring
- Node Exporter Full
- Kubernetes Pods
- Kubernetes Deployments
- Kubernetes StatefulSets

## Custom Dashboards

Import these Grafana dashboard IDs:
- **15760** - Kubernetes Views Global
- **15757** - Kubernetes Views Pods
- **15758** - Kubernetes Views Namespaces
- **13770** - Kubernetes Cluster Cost Analysis

## ServiceMonitors

ServiceMonitors are automatically created for:
- kube-state-metrics
- node-exporter
- kubelet
- apiserver

## Alerting

AlertManager is included and pre-configured with basic alerts:
- Node down
- High CPU usage
- High memory usage
- Pod crash looping
- Persistent volume filling up

## Cost Tracking

To track costs, use the Kubecost integration:

```bash
helm install kubecost kubecost/cost-analyzer \
  --namespace monitoring \
  --set prometheus.fqdn=http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090
```

Access Kubecost: `kubectl port-forward -n monitoring svc/kubecost-cost-analyzer 9090:9090`

## Cleanup

```bash
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring
```
