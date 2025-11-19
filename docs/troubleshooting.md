# Troubleshooting Guide

## Common Issues

### 1. Pods Not Starting

#### Symptoms
```bash
kubectl get pods -n monitoring
# Shows pods in Pending or CrashLoopBackOff state
```

#### Solutions

**Check pod events:**
```bash
kubectl describe pod <pod-name> -n monitoring
```

**Common causes:**
- Insufficient resources: Scale up node group
- Image pull errors: Check image names and registry access
- PVC not bound: Check storage class and EBS CSI driver

**Fix storage issues:**
```bash
# Check PVCs
kubectl get pvc -n monitoring

# Check storage class
kubectl get storageclass

# Verify EBS CSI driver
kubectl get pods -n kube-system | grep ebs-csi
```

### 2. Prometheus Not Scraping Targets

#### Symptoms
- Targets show as "DOWN" in Prometheus UI
- No metrics appearing in Grafana

#### Solutions

**Check Prometheus logs:**
```bash
kubectl logs -n monitoring deployment/prometheus
```

**Verify service discovery:**
```bash
# Check if services are discoverable
kubectl get svc -A

# Check Prometheus config
kubectl get configmap prometheus-config -n monitoring -o yaml
```

**Test connectivity:**
```bash
# Exec into Prometheus pod
kubectl exec -it -n monitoring deployment/prometheus -- sh

# Test scraping endpoint
wget -O- http://node-exporter:9100/metrics
```

**Fix RBAC issues:**
```bash
# Verify service account
kubectl get sa prometheus -n monitoring

# Check cluster role binding
kubectl get clusterrolebinding prometheus
```

### 3. Grafana Can't Connect to Prometheus

#### Symptoms
- "Bad Gateway" or connection errors in Grafana
- Dashboards show "No data"

#### Solutions

**Check Grafana logs:**
```bash
kubectl logs -n monitoring deployment/grafana
```

**Verify datasource configuration:**
```bash
kubectl get configmap grafana-datasources -n monitoring -o yaml
```

**Test connectivity:**
```bash
# Exec into Grafana pod
kubectl exec -it -n monitoring deployment/grafana -- sh

# Test Prometheus connection
wget -O- http://prometheus:9090/api/v1/query?query=up
```

**Fix datasource:**
1. Login to Grafana
2. Go to Configuration → Data Sources
3. Edit Prometheus datasource
4. URL should be: `http://prometheus:9090`
5. Click "Save & Test"

### 4. AlertManager Not Sending Alerts

#### Symptoms
- Alerts firing in Prometheus but not received
- AlertManager shows alerts but no notifications

#### Solutions

**Check AlertManager logs:**
```bash
kubectl logs -n monitoring deployment/alertmanager
```

**Verify configuration:**
```bash
kubectl get configmap alertmanager-config -n monitoring -o yaml
```

**Test webhook:**
```bash
# Test Slack webhook
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test alert"}' \
  YOUR_SLACK_WEBHOOK_URL
```

**Common issues:**
- Invalid webhook URL
- Incorrect routing rules
- Inhibition rules blocking alerts

**Reload configuration:**
```bash
kubectl rollout restart deployment/alertmanager -n monitoring
```

### 5. High Memory Usage

#### Symptoms
- Pods being OOMKilled
- Node memory pressure

#### Solutions

**Check resource usage:**
```bash
kubectl top nodes
kubectl top pods -n monitoring
kubectl top pods -n shopmetrics
```

**Adjust resource limits:**
```bash
# Edit deployment
kubectl edit deployment prometheus -n monitoring

# Increase memory limits
resources:
  limits:
    memory: 8Gi
```

**Reduce Prometheus retention:**
```bash
# Edit Prometheus args
--storage.tsdb.retention.time=7d
```

**Scale nodes:**
```bash
# Increase node count
kubectl scale deployment/prometheus --replicas=1 -n monitoring
```

### 6. Ingress Not Working

#### Symptoms
- Cannot access Grafana/Prometheus via domain
- 404 or 502 errors

#### Solutions

**Check ingress status:**
```bash
kubectl get ingress -n monitoring
kubectl describe ingress monitoring-ingress -n monitoring
```

**Verify ALB controller:**
```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Check ALB in AWS Console:**
- Verify ALB is created
- Check target groups
- Verify health checks passing

**Common issues:**
- Missing ALB controller
- Incorrect annotations
- Security group blocking traffic
- Certificate ARN invalid

**Fix ALB controller:**
```bash
# Install ALB controller if missing
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=shopmetrics-eks-production
```

### 7. Metrics Not Appearing

#### Symptoms
- Application metrics not showing in Prometheus
- Empty graphs in Grafana

#### Solutions

**Verify application is exposing metrics:**
```bash
# Port forward to application
kubectl port-forward -n shopmetrics deployment/product-service 8081:8081

# Check metrics endpoint
curl http://localhost:8081/metrics
```

**Check Prometheus scrape config:**
```bash
kubectl get configmap prometheus-config -n monitoring -o yaml | grep -A 20 "job_name: 'shopmetrics"
```

**Verify pod annotations:**
```bash
kubectl get pod -n shopmetrics -o yaml | grep -A 5 annotations
```

Required annotations:
```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "8081"
prometheus.io/path: "/metrics"
```

### 8. Node Exporter Issues

#### Symptoms
- No node metrics in Prometheus
- Infrastructure dashboards empty

#### Solutions

**Check DaemonSet:**
```bash
kubectl get daemonset node-exporter -n monitoring
kubectl get pods -n monitoring -l app=node-exporter
```

**Check logs:**
```bash
kubectl logs -n monitoring daemonset/node-exporter
```

**Verify host access:**
```bash
# Node exporter needs hostNetwork and hostPID
kubectl get daemonset node-exporter -n monitoring -o yaml | grep -A 5 hostNetwork
```

### 9. Database Connection Issues

#### Symptoms
- Application pods crashing
- "Connection refused" errors

#### Solutions

**Check secrets:**
```bash
kubectl get secret database-credentials -n shopmetrics -o yaml
```

**Verify database connectivity:**
```bash
# Exec into application pod
kubectl exec -it -n shopmetrics deployment/product-service -- sh

# Test database connection
nc -zv product-db 5432
```

**Check database pods (if running in cluster):**
```bash
kubectl get pods -n shopmetrics | grep db
kubectl logs -n shopmetrics <db-pod-name>
```

### 10. Performance Issues

#### Symptoms
- Slow dashboard loading
- High query latency
- Prometheus using too much CPU

#### Solutions

**Optimize Prometheus queries:**
- Use recording rules for complex queries
- Reduce scrape frequency
- Limit metric cardinality

**Add recording rules:**
```yaml
# Add to prometheus-rules.yaml
groups:
  - name: recording_rules
    interval: 30s
    rules:
      - record: job:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (job)
```

**Reduce retention:**
```bash
# Edit Prometheus deployment
--storage.tsdb.retention.time=7d
--storage.tsdb.retention.size=45GB
```

**Use remote storage:**
- Configure Prometheus remote write to Cortex/Thanos
- Offload long-term storage

## Getting Help

### Collect Diagnostic Information

```bash
# Create diagnostic bundle
mkdir diagnostics
kubectl get all -n monitoring > diagnostics/monitoring-resources.txt
kubectl get all -n shopmetrics > diagnostics/shopmetrics-resources.txt
kubectl describe nodes > diagnostics/nodes.txt
kubectl top nodes > diagnostics/node-usage.txt
kubectl top pods -A > diagnostics/pod-usage.txt

# Collect logs
kubectl logs -n monitoring deployment/prometheus > diagnostics/prometheus.log
kubectl logs -n monitoring deployment/grafana > diagnostics/grafana.log
kubectl logs -n monitoring deployment/alertmanager > diagnostics/alertmanager.log

# Create archive
tar czf diagnostics.tar.gz diagnostics/
```

### Useful Commands

```bash
# Watch pod status
kubectl get pods -n monitoring -w

# Stream logs
kubectl logs -f -n monitoring deployment/prometheus

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Resource usage
kubectl top pods -n monitoring --containers

# Describe all resources
kubectl describe all -n monitoring
```

### Contact Support

Include the diagnostic bundle and:
- Kubernetes version: `kubectl version`
- EKS cluster info: `aws eks describe-cluster --name <cluster-name>`
- Error messages and logs
- Steps to reproduce the issue
