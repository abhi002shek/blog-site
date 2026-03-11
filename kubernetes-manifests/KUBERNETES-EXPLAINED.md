# Kubernetes Manifests - Deep Dive Explanation 🚀

This document provides an ultra-detailed explanation of every Kubernetes manifest file in this project. Perfect for learning Kubernetes concepts!

## 📋 Table of Contents

1. [Storage Class](#1-storage-class)
2. [Sealed Secrets](#2-sealed-secrets)
3. [MongoDB StatefulSet](#3-mongodb-statefulset)
4. [Services](#4-services)
5. [ConfigMaps](#5-configmaps)
6. [Deployments](#6-deployments)
7. [Ingress](#7-ingress)
8. [Horizontal Pod Autoscaler](#8-horizontal-pod-autoscaler)
9. [Network Policies](#9-network-policies)
10. [Kustomization](#10-kustomization)

---

## 1. Storage Class

**File:** `storage-class.yml`

### What is it?

A StorageClass defines how dynamic storage volumes are provisioned in Kubernetes. It's like a "template" for creating persistent volumes.

### Why is it needed?

- MongoDB needs persistent storage that survives pod restarts
- Without StorageClass, you'd manually create volumes (not scalable)
- Enables dynamic provisioning - volumes created automatically when requested

### Deep Dive

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
```

**apiVersion: storage.k8s.io/v1**
- API group for storage resources
- `v1` = stable, production-ready API

**kind: StorageClass**
- Resource type
- Defines storage provisioning behavior

**metadata.name: ebs-sc**
- Unique identifier for this StorageClass
- Referenced by PersistentVolumeClaims (PVCs)

```yaml
provisioner: ebs.csi.aws.com
```

**provisioner: ebs.csi.aws.com**
- Driver that creates the actual volumes
- `ebs.csi.aws.com` = AWS EBS CSI driver
- CSI = Container Storage Interface (standard for storage plugins)
- This driver talks to AWS APIs to create EBS volumes

```yaml
parameters:
  type: gp3
  encrypted: "true"
```

**parameters.type: gp3**
- EBS volume type
- **gp3** = General Purpose SSD (latest generation)
- Alternatives: gp2 (older), io1 (high performance), st1 (throughput optimized)
- gp3 advantages:
  - 20% cheaper than gp2
  - Better baseline performance (3000 IOPS, 125 MB/s)
  - Can independently scale IOPS and throughput

**parameters.encrypted: "true"**
- Encrypts data at rest using AWS KMS
- Security best practice
- No performance penalty
- Protects against physical disk theft

```yaml
volumeBindingMode: WaitForFirstConsumer
```

**volumeBindingMode: WaitForFirstConsumer**
- **Critical for multi-AZ clusters!**
- Delays volume creation until pod is scheduled
- **Why?** EBS volumes are AZ-specific
- **Without this:** Volume created in us-east-1a, pod scheduled in us-east-1b → pod can't attach volume!
- **With this:** Pod scheduled in us-east-1b → volume created in us-east-1b → success!

```yaml
reclaimPolicy: Retain
```

**reclaimPolicy: Retain**
- What happens to volume when PVC is deleted?
- **Retain** = Keep the volume (manual cleanup required)
- **Delete** = Automatically delete volume (data loss!)
- **Recycle** = Deprecated, don't use
- **Best practice:** Use Retain for databases to prevent accidental data loss

```yaml
allowVolumeExpansion: true
```

**allowVolumeExpansion: true**
- Allows resizing volumes without downtime
- Example: 10GB → 20GB without recreating volume
- **How it works:**
  1. Edit PVC, increase size
  2. CSI driver resizes EBS volume
  3. Filesystem automatically expanded
- **Limitation:** Can only increase, not decrease

### How it works with other resources

1. **StatefulSet** creates **PersistentVolumeClaim (PVC)**
2. PVC references this **StorageClass** by name
3. StorageClass tells **EBS CSI Driver** to create volume
4. Driver creates **EBS volume** in AWS
5. Kubernetes creates **PersistentVolume (PV)** representing the EBS volume
6. PV binds to PVC
7. Pod mounts PVC as a volume

### Best Practices

✅ Use `gp3` for cost savings
✅ Always encrypt (`encrypted: "true"`)
✅ Use `WaitForFirstConsumer` for multi-AZ
✅ Use `Retain` for databases
✅ Enable `allowVolumeExpansion`
❌ Don't use `Delete` for production databases

---

## 2. Sealed Secrets

**Files:** `mongo-sealedsecret.yml`, `backend-sealedsecret.yml`

### What is it?

SealedSecret is an encrypted version of a Kubernetes Secret that can be safely stored in Git.

### Why is it needed?

**Problem:** Regular Kubernetes Secrets are only base64 encoded (not encrypted)
```yaml
# Regular secret - NOT SECURE!
apiVersion: v1
kind: Secret
data:
  password: bW9uZ29kYjEyMw==  # Just base64, anyone can decode!
```

**Solution:** SealedSecrets encrypt with a cluster-specific key
- Only the cluster with the private key can decrypt
- Safe to commit to Git
- Part of GitOps workflow

### Deep Dive

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: mongo-secrets
  namespace: default
```

**apiVersion: bitnami.com/v1alpha1**
- Custom Resource Definition (CRD) from Bitnami
- Not a native Kubernetes resource
- Requires Sealed Secrets controller to be installed

**kind: SealedSecret**
- Custom resource type
- Controller watches for these and decrypts them

```yaml
spec:
  encryptedData:
    MONGO_INITDB_ROOT_USERNAME: AgBX7k2...encrypted...
    MONGO_INITDB_ROOT_PASSWORD: AgCY9m3...encrypted...
```

**encryptedData**
- Encrypted key-value pairs
- Encrypted using cluster's public key
- **Encryption algorithm:** RSA-2048 + AES-256-GCM
- Each cluster has unique key pair (generated by controller)

**How encryption works:**
1. You run: `kubeseal < secret.yaml > sealedsecret.yaml`
2. kubeseal fetches cluster's public key
3. Encrypts each value with public key
4. Only cluster's private key can decrypt

```yaml
template:
  metadata:
    name: mongo-secrets
    namespace: default
  type: Opaque
```

**template**
- Defines the Secret that will be created after decryption
- Controller creates this Secret automatically

**type: Opaque**
- Generic secret type (arbitrary key-value pairs)
- Other types: `kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`

### How it works

```
┌─────────────────────────────────────────────────────────┐
│  1. Developer creates regular Secret                     │
│     kubectl create secret generic mongo-secrets ...      │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  2. Encrypt with kubeseal                                │
│     kubeseal < secret.yaml > sealedsecret.yaml          │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  3. Commit SealedSecret to Git (safe!)                   │
│     git add sealedsecret.yaml && git commit              │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  4. Apply to cluster                                     │
│     kubectl apply -f sealedsecret.yaml                   │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  5. Sealed Secrets Controller detects it                 │
│     - Decrypts using cluster's private key               │
│     - Creates regular Secret                             │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  6. Pods can now use the Secret                          │
│     envFrom: secretRef: name: mongo-secrets              │
└─────────────────────────────────────────────────────────┘
```

### Security Features

**Scope-based encryption:**
- **Strict:** Encrypted for specific namespace + name (most secure)
- **Namespace-wide:** Can be renamed within namespace
- **Cluster-wide:** Can be used anywhere (least secure)

**Key rotation:**
- Controller generates new key pair every 30 days
- Old keys kept for decryption (backward compatibility)
- Re-seal secrets with new key periodically

### Best Practices

✅ Use strict scope (default)
✅ Rotate sealed secrets every 90 days
✅ Never commit regular Secrets to Git
✅ Backup controller's private key (for disaster recovery)
❌ Don't share sealed secrets between clusters
❌ Don't decrypt sealed secrets locally (defeats purpose)

---

## 3. MongoDB StatefulSet

**File:** `mongo-sts.yml`

### What is it?

StatefulSet is a Kubernetes workload for stateful applications that need:
- Stable network identity
- Persistent storage
- Ordered deployment/scaling

### Why StatefulSet instead of Deployment?

| Feature | Deployment | StatefulSet |
|---------|-----------|-------------|
| Pod names | Random (mongo-7f8d9c-xyz) | Ordered (mongo-0, mongo-1) |
| Network identity | Changes on restart | Stable (mongo-0.mongo-service) |
| Storage | Shared or ephemeral | Dedicated per pod |
| Scaling | Parallel | Sequential (0→1→2) |
| Use case | Stateless apps | Databases, queues |

### Deep Dive

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
spec:
  serviceName: mongo-service
```

**serviceName: mongo-service**
- **Critical field!** Links to headless Service
- Creates DNS entries: `mongo-0.mongo-service.default.svc.cluster.local`
- Each pod gets unique DNS name
- **Why?** MongoDB replica set needs stable addresses

```yaml
replicas: 2
```

**replicas: 2**
- Number of MongoDB instances
- **Why 2?** 
  - High availability (if one fails, other serves)
  - Not 3 because: cost vs benefit (3 nodes = $45/month more)
  - Production: Use 3 for true quorum

```yaml
selector:
  matchLabels:
    app: mongo
```

**selector.matchLabels**
- How StatefulSet finds its pods
- Must match `template.metadata.labels`
- Immutable after creation

```yaml
template:
  metadata:
    labels:
      app: mongo
  spec:
    terminationGracePeriodSeconds: 10
```

**terminationGracePeriodSeconds: 10**
- Time given to pod for graceful shutdown
- **What happens:**
  1. Kubernetes sends SIGTERM to container
  2. Waits 10 seconds
  3. If still running, sends SIGKILL (force kill)
- **Why 10s?** MongoDB needs time to:
  - Flush writes to disk
  - Close connections
  - Update replica set status
- Default is 30s, 10s is acceptable for small databases

```yaml
containers:
  - name: mongo
    image: mongo:7.0
    ports:
      - containerPort: 27017
        name: mongo
```

**image: mongo:7.0**
- Official MongoDB image
- Version 7.0 = Latest stable (as of 2024)
- **Best practice:** Pin major version, not `latest`

**ports.name: mongo**
- Named port (optional but recommended)
- Can reference by name in Services: `targetPort: mongo`
- Self-documenting

```yaml
env:
  - name: MONGO_INITDB_ROOT_USERNAME
    valueFrom:
      secretKeyRef:
        name: mongo-secrets
        key: MONGO_INITDB_ROOT_USERNAME
```

**valueFrom.secretKeyRef**
- Injects secret value as environment variable
- **More secure than:** `value: "admin"` (hardcoded)
- Secret updated → pod must restart to see new value

```yaml
volumeMounts:
  - name: mongo-storage
    mountPath: /data/db
```

**mountPath: /data/db**
- MongoDB's default data directory
- All databases, collections, indexes stored here
- **Critical:** Must be persistent volume!

```yaml
volumeClaimTemplates:
  - metadata:
      name: mongo-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-sc
      resources:
        requests:
          storage: 5Gi
```

**volumeClaimTemplates**
- **Key feature of StatefulSets!**
- Creates one PVC per pod automatically
- PVCs named: `mongo-storage-mongo-0`, `mongo-storage-mongo-1`
- **Lifecycle:** PVCs persist even if StatefulSet deleted (data safety)

**accessModes: ReadWriteOnce**
- **RWO** = One node can mount for read-write
- **ROX** = Many nodes can mount read-only
- **RWX** = Many nodes can mount read-write
- **Why RWO?** EBS volumes can only attach to one EC2 instance
- **Implication:** Pod and volume must be in same AZ

**storage: 5Gi**
- Initial volume size
- Can be expanded later (thanks to `allowVolumeExpansion: true`)
- **Cost:** ~$0.50/month for 5GB gp3

### StatefulSet Lifecycle

**Deployment (0 → 2 replicas):**
```
1. Create mongo-0
   ├─ Create PVC mongo-storage-mongo-0
   ├─ Wait for PVC bound
   ├─ Wait for pod Ready
2. Create mongo-1 (only after mongo-0 is Ready!)
   ├─ Create PVC mongo-storage-mongo-1
   ├─ Wait for PVC bound
   ├─ Wait for pod Ready
```

**Scaling down (2 → 1):**
```
1. Delete mongo-1 (highest ordinal first)
   ├─ Graceful shutdown (10s)
   ├─ Pod deleted
   ├─ PVC mongo-storage-mongo-1 RETAINED
```

**Scaling up (1 → 2):**
```
1. Create mongo-1
   ├─ Reuse existing PVC mongo-storage-mongo-1
   ├─ Data still there!
```

### Best Practices

✅ Use headless Service
✅ Set appropriate `terminationGracePeriodSeconds`
✅ Use `volumeClaimTemplates` for persistent data
✅ Pin image versions (not `latest`)
✅ Set resource limits (prevent resource exhaustion)
❌ Don't delete PVCs manually (data loss!)
❌ Don't use Deployment for databases


---

## 4. Services

**Files:** `mongo-service.yml`, `backend-service.yml`, `frontend-service.yml`

### What is a Service?

A Service is a stable network endpoint for accessing pods. Think of it as a load balancer + DNS name for your pods.

### Why is it needed?

**Problem:** Pods have dynamic IPs that change on restart
```
mongo-0: 10.0.1.5 → restart → 10.0.1.23 (IP changed!)
```

**Solution:** Service provides stable IP and DNS name
```
mongo-service: 10.96.0.10 (never changes)
DNS: mongo-service.default.svc.cluster.local
```

### Service Types

| Type | Use Case | Example |
|------|----------|---------|
| ClusterIP | Internal only | mongo-service, backend-service |
| NodePort | External (dev) | Exposes on node IP:port |
| LoadBalancer | External (prod) | Creates cloud load balancer |
| Headless | StatefulSet | mongo-service (clusterIP: None) |

### Deep Dive: mongo-service.yml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mongo-service
spec:
  clusterIP: None
```

**clusterIP: None**
- **Headless Service** - no load balancing!
- **Why?** StatefulSets need direct pod access
- **Result:** DNS returns pod IPs directly, not service IP
- **DNS entries created:**
  - `mongo-service.default.svc.cluster.local` → All pod IPs
  - `mongo-0.mongo-service.default.svc.cluster.local` → mongo-0's IP
  - `mongo-1.mongo-service.default.svc.cluster.local` → mongo-1's IP

**Use case:** MongoDB replica set configuration
```javascript
// MongoDB connects to specific replicas
rs.initiate({
  members: [
    { _id: 0, host: "mongo-0.mongo-service:27017" },
    { _id: 1, host: "mongo-1.mongo-service:27017" }
  ]
})
```

```yaml
selector:
  app: mongo
ports:
  - port: 27017
    targetPort: 27017
    protocol: TCP
```

**selector.app: mongo**
- Service routes traffic to pods with this label
- Dynamic: New pods with label automatically added

**port: 27017**
- Port exposed by the Service
- Other pods connect to: `mongo-service:27017`

**targetPort: 27017**
- Port on the pod container
- Can be different from `port`
- Example: `port: 80, targetPort: 8080`

### Deep Dive: backend-service.yml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
    - port: 5000
      targetPort: 5000
      protocol: TCP
```

**type: ClusterIP** (default)
- Internal-only service
- Gets a stable cluster IP (e.g., 10.96.0.15)
- **Not accessible** from outside cluster
- **Accessible from:**
  - Other pods: `http://backend-service:5000`
  - Ingress controller: Routes external traffic here

**How it works:**
```
Frontend pod → backend-service:5000 → Load balanced to backend pods
                                    ├─ backend-7f8d9c-abc (10.0.1.10:5000)
                                    ├─ backend-7f8d9c-def (10.0.1.11:5000)
                                    └─ backend-7f8d9c-ghi (10.0.1.12:5000)
```

### Deep Dive: frontend-service.yml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
```

**port: 80, targetPort: 80**
- Service listens on port 80
- Forwards to container port 80 (nginx)
- **Why 80?** Standard HTTP port

**Accessed via Ingress:**
```
User → ALB → Ingress → frontend-service:80 → frontend pods
```

### Service Discovery

**Environment Variables (automatic):**
```bash
# Kubernetes injects these into every pod
BACKEND_SERVICE_SERVICE_HOST=10.96.0.15
BACKEND_SERVICE_SERVICE_PORT=5000
```

**DNS (recommended):**
```bash
# Short name (same namespace)
curl http://backend-service:5000

# FQDN (any namespace)
curl http://backend-service.default.svc.cluster.local:5000
```

### Load Balancing

Services use **iptables** or **IPVS** for load balancing:

**iptables mode (default):**
- Random selection
- No health checking at service level
- Fast but less features

**IPVS mode (advanced):**
- Multiple algorithms: round-robin, least-connection
- Better performance for many services
- Enable with: `kube-proxy --proxy-mode=ipvs`

### Best Practices

✅ Use ClusterIP for internal services
✅ Use headless for StatefulSets
✅ Use DNS names, not IPs
✅ Name ports for clarity
❌ Don't use LoadBalancer for internal services (costs money!)
❌ Don't hardcode service IPs

---

## 5. ConfigMaps

**Files:** `backend-config.yml`, `frontend-config.yml`

### What is a ConfigMap?

ConfigMap stores non-sensitive configuration data as key-value pairs.

### Why is it needed?

**Problem:** Hardcoded configuration in images
```dockerfile
# Bad: Hardcoded in Dockerfile
ENV API_URL=http://backend:5000
```
- Can't change without rebuilding image
- Different configs for dev/staging/prod = different images

**Solution:** ConfigMap externalizes configuration
```yaml
# Good: Externalized in ConfigMap
apiVersion: v1
kind: ConfigMap
data:
  API_URL: http://backend-service:5000
```
- Same image, different configs
- Change config without rebuilding

### Deep Dive: backend-config.yml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
data:
  PORT: "5000"
```

**data.PORT: "5000"**
- **Must be string!** Even numbers
- **Why?** ConfigMaps only store strings
- Container receives: `PORT=5000` (as string)

**Usage in pod:**
```yaml
envFrom:
  - configMapRef:
      name: backend-config
```
- Injects all keys as environment variables
- Alternative: `env[].valueFrom.configMapKeyRef` (single key)

### Deep Dive: frontend-config.yml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
data:
  REACT_APP_API_URL: http://backend-service:5000
```

**REACT_APP_API_URL**
- React convention: `REACT_APP_*` prefix
- Available in React: `process.env.REACT_APP_API_URL`
- **Important:** Must be set at build time for React!

**Build-time vs Runtime:**
- **Build-time:** Baked into JavaScript bundle
- **Runtime:** Read from environment when container starts
- **React:** Build-time (uses webpack)
- **Node.js:** Runtime (uses process.env)

### ConfigMap Patterns

**1. Environment Variables (current approach):**
```yaml
envFrom:
  - configMapRef:
      name: backend-config
```
✅ Simple
❌ Requires pod restart to update

**2. Volume Mount:**
```yaml
volumes:
  - name: config
    configMap:
      name: backend-config
volumeMounts:
  - name: config
    mountPath: /etc/config
```
✅ Can update without restart (if app watches file)
❌ More complex

**3. Single Key:**
```yaml
env:
  - name: PORT
    valueFrom:
      configMapKeyRef:
        name: backend-config
        key: PORT
```
✅ Explicit, clear
❌ Verbose for many keys

### Updating ConfigMaps

**Immutable ConfigMaps (recommended for production):**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config-v2
immutable: true
data:
  PORT: "5000"
```
✅ Prevents accidental changes
✅ Forces versioning (backend-config-v1, v2, v3)
✅ Easy rollback
❌ Must update pod spec to use new version

### Best Practices

✅ Use ConfigMaps for non-sensitive data
✅ Version ConfigMaps (backend-config-v1, v2)
✅ Use `immutable: true` in production
✅ Document what each key does
❌ Don't store secrets in ConfigMaps (use Secrets!)
❌ Don't store large files (>1MB)

---

## 6. Deployments

**Files:** `backend.yml`, `frontend.yml`

### What is a Deployment?

Deployment manages ReplicaSets, which manage Pods. It provides:
- Declarative updates
- Rolling updates
- Rollback capability
- Scaling

### Deployment Hierarchy

```
Deployment (desired state: 2 replicas, image: v2)
    ↓
ReplicaSet-v2 (manages 2 pods with image v2)
    ↓
Pods (actual running containers)
```

### Deep Dive: frontend.yml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
  labels:
    app: frontend
```

**metadata.labels**
- Labels on the Deployment itself
- Different from pod labels
- Used for organizing/filtering Deployments

```yaml
spec:
  replicas: 2
```

**replicas: 2**
- Desired number of pods
- ReplicaSet ensures exactly 2 pods running
- If pod crashes → new pod created automatically
- **Why 2?**
  - High availability (one fails, other serves)
  - Load distribution
  - Zero-downtime deployments

```yaml
selector:
  matchLabels:
    app: frontend
```

**selector.matchLabels**
- How Deployment finds its pods
- **Must match** `template.metadata.labels`
- **Immutable** after creation (can't change)

```yaml
template:
  metadata:
    labels:
      app: frontend
```

**template**
- Pod template
- Blueprint for creating pods
- All pods created from this template

```yaml
spec:
  terminationGracePeriodSeconds: 10
```

**terminationGracePeriodSeconds: 10**
- Time for graceful shutdown
- **Process:**
  1. Pod marked for termination
  2. Removed from Service endpoints (no new traffic)
  3. SIGTERM sent to container
  4. Wait 10 seconds
  5. SIGKILL if still running

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: frontend
        topologyKey: topology.kubernetes.io/zone
```

**podAntiAffinity**
- **Anti-affinity** = "Don't schedule together"
- **Affinity** = "Schedule together"

**requiredDuringSchedulingIgnoredDuringExecution**
- **Required** = Hard rule (must be satisfied)
- **Preferred** = Soft rule (try to satisfy)
- **DuringScheduling** = Applies when pod is being scheduled
- **IgnoredDuringExecution** = Doesn't evict running pods if rule violated

**topologyKey: topology.kubernetes.io/zone**
- **Zone** = Availability Zone (us-east-1a, us-east-1b)
- **Effect:** Spread pods across different AZs
- **Why?** If one AZ fails, other pods still running

**Example:**
```
AZ us-east-1a: frontend-pod-1
AZ us-east-1b: frontend-pod-2
```
If us-east-1a fails → frontend-pod-2 still serves traffic!

```yaml
containers:
  - name: frontend
    image: blog-site-frontend
```

**image: blog-site-frontend**
- **Not a full image name!** Kustomize transforms this
- Kustomize replaces with: `abhi00shek/blog-site-frontend:v1-abc123`
- **Why?** Declarative image management

```yaml
ports:
  - containerPort: 80
```

**containerPort: 80**
- Port container listens on
- **Informational only!** Doesn't actually open port
- Used by Services to know which port to target

```yaml
envFrom:
  - configMapRef:
      name: frontend-config
```

**envFrom.configMapRef**
- Injects all ConfigMap keys as environment variables
- **Alternative:** `env[].valueFrom` for individual keys

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

**resources.requests**
- **Minimum** resources guaranteed
- Scheduler uses this to place pod on node
- **memory: 128Mi** = 128 Mebibytes (134 MB)
- **cpu: 100m** = 100 millicores = 0.1 CPU core

**resources.limits**
- **Maximum** resources allowed
- **Memory limit exceeded** → Pod killed (OOMKilled)
- **CPU limit exceeded** → Throttled (not killed)

**Why set both?**
- **Requests:** Ensure pod gets minimum resources
- **Limits:** Prevent pod from consuming all node resources

**QoS Classes (Quality of Service):**
- **Guaranteed:** requests = limits (highest priority)
- **Burstable:** requests < limits (medium priority)
- **BestEffort:** no requests/limits (lowest priority, killed first)

```yaml
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**livenessProbe**
- **Purpose:** Is the app alive?
- **Action if fails:** Restart container
- **Use case:** Detect deadlocks, infinite loops

**httpGet**
- HTTP GET request to path
- **Success:** HTTP 200-399
- **Failure:** HTTP 400+, timeout, connection refused

**initialDelaySeconds: 30**
- Wait 30s before first probe
- **Why?** App needs time to start
- Too short → false failures during startup

**periodSeconds: 10**
- Check every 10 seconds
- **Trade-off:** Faster detection vs more overhead

**timeoutSeconds: 5**
- Wait 5s for response
- **Timeout = failure**

**failureThreshold: 3**
- Fail 3 times before restarting
- **Why not 1?** Avoid restarts due to temporary glitches
- **Calculation:** 3 failures × 10s period = 30s to detect failure

```yaml
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

**readinessProbe**
- **Purpose:** Is the app ready to serve traffic?
- **Action if fails:** Remove from Service endpoints
- **Use case:** Warm-up period, dependency checks

**Difference from livenessProbe:**
| Probe | Failure Action | Use Case |
|-------|---------------|----------|
| Liveness | Restart container | Detect crashes |
| Readiness | Remove from Service | Detect not-ready state |

**Example scenario:**
```
1. Pod starts
2. Liveness: Wait 30s, then check (app might be starting)
3. Readiness: Wait 10s, then check (app ready sooner)
4. Readiness fails → Pod not in Service (no traffic)
5. Readiness succeeds → Pod added to Service (receives traffic)
6. Liveness fails 3 times → Container restarted
```

### Rolling Update Strategy

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

**type: RollingUpdate** (default)
- Gradually replace old pods with new pods
- **Alternative:** Recreate (kill all, then create new)

**maxSurge: 1**
- Maximum extra pods during update
- **Example:** 2 replicas, maxSurge=1 → max 3 pods during update
- **Why?** Ensure capacity during rollout

**maxUnavailable: 0**
- Maximum pods that can be unavailable
- **Example:** 2 replicas, maxUnavailable=0 → always 2 pods available
- **Why?** Zero-downtime deployments

**Rolling Update Process:**
```
Initial: pod-v1-a, pod-v1-b (2 pods)
Step 1: Create pod-v2-a (3 pods, maxSurge=1)
Step 2: Wait for pod-v2-a Ready
Step 3: Delete pod-v1-a (2 pods)
Step 4: Create pod-v2-b (3 pods)
Step 5: Wait for pod-v2-b Ready
Step 6: Delete pod-v1-b (2 pods)
Final: pod-v2-a, pod-v2-b (2 pods)
```

### Best Practices

✅ Set resource requests and limits
✅ Use both liveness and readiness probes
✅ Use anti-affinity for HA
✅ Set appropriate replica count (≥2 for prod)
✅ Use rolling updates with maxUnavailable=0
❌ Don't set limits too low (OOMKilled)
❌ Don't set initialDelaySeconds too short
❌ Don't use `latest` tag


---

## 7. Ingress

**File:** `ingress.yml`

### What is an Ingress?

Ingress is an API object that manages external access to services, typically HTTP/HTTPS. It provides:
- URL routing
- Load balancing
- SSL termination
- Name-based virtual hosting

### Why is it needed?

**Without Ingress:**
```
User → LoadBalancer Service (costs $18/month)
     → frontend pods

User → Another LoadBalancer ($18/month)
     → backend pods

Total: $36/month for 2 services!
```

**With Ingress:**
```
User → Single ALB ($18/month)
     → Ingress Controller
        ├─ / → frontend-service
        └─ /api → backend-service

Total: $18/month for all services!
```

### Deep Dive

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
```

**annotations**
- Key-value pairs for controller-specific configuration
- Not part of Kubernetes core spec
- Interpreted by Ingress Controller (AWS Load Balancer Controller)

**alb.ingress.kubernetes.io/scheme: internet-facing**
- **internet-facing** = Public ALB (accessible from internet)
- **internal** = Private ALB (VPC only)
- **AWS-specific annotation**

```yaml
alb.ingress.kubernetes.io/target-type: ip
```

**target-type: ip**
- **ip** = Route to pod IPs directly
- **instance** = Route to node IPs (NodePort)
- **Why ip?**
  - Better performance (no extra hop)
  - Works with Fargate
  - More efficient health checks

**How it works:**
```
ALB Target Group:
├─ 10.0.1.5:80 (frontend-pod-1)
├─ 10.0.1.6:80 (frontend-pod-2)
└─ 10.0.2.7:5000 (backend-pod-1)
```

```yaml
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
```

**listen-ports**
- Ports ALB listens on
- JSON array format
- **Example with HTTPS:** `[{"HTTP": 80}, {"HTTPS": 443}]`

```yaml
alb.ingress.kubernetes.io/healthcheck-path: /
alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
alb.ingress.kubernetes.io/healthy-threshold-count: "2"
alb.ingress.kubernetes.io/unhealthy-threshold-count: "2"
```

**Health Check Configuration:**
- **healthcheck-path: /** = ALB sends GET / to check health
- **interval: 15s** = Check every 15 seconds
- **timeout: 5s** = Wait 5s for response
- **healthy-threshold: 2** = 2 successes → mark healthy
- **unhealthy-threshold: 2** = 2 failures → mark unhealthy

**Health Check Math:**
- **Time to mark healthy:** 2 × 15s = 30s
- **Time to mark unhealthy:** 2 × 15s = 30s

```yaml
spec:
  ingressClassName: alb
```

**ingressClassName: alb**
- Which Ingress Controller handles this Ingress
- **alb** = AWS Load Balancer Controller
- **nginx** = NGINX Ingress Controller
- **traefik** = Traefik Ingress Controller
- **Why specify?** Multiple controllers can coexist

```yaml
rules:
  - host: blogsite.duckdns.org
```

**host: blogsite.duckdns.org**
- **Name-based virtual hosting**
- ALB routes based on HTTP Host header
- **Multiple hosts supported:**
  ```yaml
  rules:
    - host: blog.example.com
    - host: api.example.com
  ```

```yaml
http:
  paths:
    - path: /
      pathType: Prefix
      backend:
        service:
          name: frontend-service
          port:
            number: 80
```

**path: /**
- URL path to match
- **/** = Match all paths starting with /

**pathType: Prefix**
- **Prefix** = Match path prefix (/, /about, /contact)
- **Exact** = Match exact path only
- **ImplementationSpecific** = Controller-specific

**Matching examples:**
| pathType | path | Matches | Doesn't Match |
|----------|------|---------|---------------|
| Prefix | / | /, /api, /about | (matches all) |
| Prefix | /api | /api, /api/users | /, /about |
| Exact | /api | /api | /api/, /api/users |

```yaml
- path: /api
  pathType: Prefix
  backend:
    service:
      name: backend-service
      port:
        number: 5000
```

**Path-based routing:**
```
blogsite.duckdns.org/         → frontend-service:80
blogsite.duckdns.org/about    → frontend-service:80
blogsite.duckdns.org/api      → backend-service:5000
blogsite.duckdns.org/api/blogs → backend-service:5000
```

**Order matters!**
- More specific paths first
- `/api` before `/`
- Otherwise `/` would match everything

### How Ingress Works

```
┌─────────────────────────────────────────────────────────────┐
│  1. User requests http://blogsite.duckdns.org/api/blogs     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  2. DNS resolves to ALB IP                                   │
│     blogsite.duckdns.org → 52.45.123.45                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  3. ALB receives request                                     │
│     Host: blogsite.duckdns.org                              │
│     Path: /api/blogs                                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  4. ALB matches Ingress rules                                │
│     Host matches: blogsite.duckdns.org ✓                    │
│     Path matches: /api (Prefix) ✓                           │
│     Route to: backend-service:5000                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  5. ALB forwards to backend pod                              │
│     Target: 10.0.1.7:5000 (backend-pod-1)                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  6. Backend pod processes request                            │
│     GET /api/blogs → Returns blog data                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  7. Response sent back through ALB to user                   │
└─────────────────────────────────────────────────────────────┘
```

### Ingress Controller

**What is it?**
- Watches Ingress resources
- Creates/updates load balancers
- Configures routing rules

**AWS Load Balancer Controller:**
1. Watches for Ingress creation
2. Calls AWS APIs to create ALB
3. Creates Target Groups for each service
4. Registers pod IPs as targets
5. Configures listener rules
6. Updates when pods change

### SSL/TLS with Ingress

**To add HTTPS:**
```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/id
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
```

**certificate-arn**
- AWS Certificate Manager (ACM) certificate
- Free SSL certificates from AWS
- Auto-renewal

**ssl-redirect: "443"**
- Redirect HTTP → HTTPS
- Security best practice

### Best Practices

✅ Use `target-type: ip` for better performance
✅ Set appropriate health check intervals
✅ Use HTTPS in production
✅ Order paths from specific to general
✅ Use `ingressClassName` for clarity
❌ Don't use `pathType: ImplementationSpecific` (not portable)
❌ Don't expose sensitive endpoints without authentication

---

## 8. Horizontal Pod Autoscaler (HPA)

**Files:** `frontend-hpa.yml`, `backend-hpa.yml`

### What is HPA?

HPA automatically scales the number of pods based on metrics (CPU, memory, custom metrics).

### Why is it needed?

**Problem:** Fixed replica count can't handle traffic spikes
```
Normal traffic: 100 req/s → 2 pods (50 req/s each) ✓
Traffic spike: 1000 req/s → 2 pods (500 req/s each) ✗ Overloaded!
```

**Solution:** HPA scales automatically
```
Traffic spike: 1000 req/s → HPA scales to 10 pods (100 req/s each) ✓
```

### Deep Dive

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
```

**apiVersion: autoscaling/v2**
- **v2** = Latest stable API (supports multiple metrics)
- **v1** = Deprecated (CPU only)
- **v2beta2** = Beta (don't use in production)

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend-deployment
```

**scaleTargetRef**
- What to scale
- Can target: Deployment, ReplicaSet, StatefulSet
- **Cannot target:** DaemonSet (one pod per node by design)

```yaml
minReplicas: 2
maxReplicas: 10
```

**minReplicas: 2**
- Minimum pods (never scale below)
- **Why 2?** High availability

**maxReplicas: 10**
- Maximum pods (never scale above)
- **Why limit?** Cost control, resource limits
- **Calculation:** 10 pods × 200m CPU = 2 CPU cores max

```yaml
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**type: Resource**
- Built-in resource metrics (CPU, memory)
- **Alternatives:**
  - **Pods** = Custom metrics per pod
  - **Object** = Metrics from other objects
  - **External** = External metrics (e.g., queue length)

**name: cpu**
- Metric to track
- **cpu** = CPU utilization
- **memory** = Memory utilization

**averageUtilization: 70**
- Target average across all pods
- **70%** = Scale when average CPU > 70%
- **Why 70%?** 
  - Not too low (wasteful)
  - Not too high (no headroom for spikes)
  - Industry standard: 60-80%

**How it calculates:**
```
Current pods: 2
Current CPU: 85% average
Target CPU: 70%

Desired replicas = ceil(2 × (85 / 70)) = ceil(2.43) = 3 pods
```

```yaml
- type: Resource
  resource:
    name: memory
    target:
      type: Utilization
      averageUtilization: 80
```

**memory target: 80%**
- Scale when average memory > 80%
- **Higher than CPU (80% vs 70%)** because:
  - Memory usage more stable
  - Memory doesn't spike as quickly as CPU

**Multiple metrics:**
- HPA evaluates ALL metrics
- Scales to satisfy ALL targets
- **Example:**
  - CPU says: need 3 pods
  - Memory says: need 4 pods
  - **Result:** Scale to 4 pods (highest)

```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300
    policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

**behavior** (v2 feature)
- Fine-tune scaling behavior
- Prevent flapping (rapid scale up/down)

**scaleDown.stabilizationWindowSeconds: 300**
- Wait 5 minutes before scaling down
- **Why?** Traffic might spike again
- **Prevents:** Scale down → spike → scale up → repeat

**policies.type: Percent**
- Scale by percentage
- **Alternative:** Pods (absolute number)

**value: 50**
- Scale down by max 50% at a time
- **Example:** 10 pods → max 5 pods removed
- **Why?** Gradual scale-down prevents disruption

**periodSeconds: 60**
- Evaluate every 60 seconds
- **Calculation:** Every minute, can remove up to 50% of pods

```yaml
scaleUp:
  stabilizationWindowSeconds: 0
  policies:
    - type: Percent
      value: 100
      periodSeconds: 30
    - type: Pods
      value: 2
      periodSeconds: 30
  selectPolicy: Max
```

**scaleUp.stabilizationWindowSeconds: 0**
- No delay for scaling up
- **Why?** Need to respond quickly to traffic spikes

**policies (multiple):**
1. **Percent: 100%** = Double pods every 30s
2. **Pods: 2** = Add 2 pods every 30s

**selectPolicy: Max**
- Use the policy that scales more
- **Example:**
  - Current: 3 pods
  - Policy 1: 100% = 6 pods (add 3)
  - Policy 2: +2 pods = 5 pods (add 2)
  - **Result:** Use Policy 1 (add 3 pods)

**Why two policies?**
- **Small scale:** Pods policy faster (2 vs 1)
- **Large scale:** Percent policy faster (10 vs 2)

### HPA Algorithm

**Calculation every 15 seconds (default):**
```
desiredReplicas = ceil(currentReplicas × (currentMetric / targetMetric))
```

**Example:**
```
Current: 4 pods, 85% CPU
Target: 70% CPU

desiredReplicas = ceil(4 × (85 / 70))
                = ceil(4 × 1.21)
                = ceil(4.86)
                = 5 pods

Action: Scale up from 4 to 5 pods
```

### Metrics Server Requirement

**HPA requires Metrics Server:**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**What it does:**
- Collects resource metrics from kubelets
- Provides metrics API for HPA
- **Without it:** HPA shows "unknown" for metrics

### Best Practices

✅ Set minReplicas ≥ 2 for HA
✅ Use 60-80% CPU target
✅ Use 70-90% memory target
✅ Set stabilizationWindow for scale-down
✅ Use multiple metrics (CPU + memory)
✅ Test with load testing tools
❌ Don't set target too low (constant scaling)
❌ Don't set maxReplicas too high (cost explosion)
❌ Don't forget to install Metrics Server

---

## 9. Network Policies

**Files:** `frontend-network-policy.yml`, `backend-network-policy.yml`, `mongo-network-policy.yml`

### What is a Network Policy?

NetworkPolicy is a firewall for pods. It controls which pods can communicate with each other.

### Why is it needed?

**Without NetworkPolicy:**
```
Any pod can talk to any pod
frontend → mongo ✓ (BAD! Frontend shouldn't access DB directly)
random-pod → mongo ✓ (BAD! Security risk)
```

**With NetworkPolicy:**
```
Only backend can talk to mongo
frontend → mongo ✗ (Blocked)
backend → mongo ✓ (Allowed)
random-pod → mongo ✗ (Blocked)
```

### Default Behavior

**Without any NetworkPolicy:**
- All traffic allowed (open)

**With at least one NetworkPolicy:**
- Default deny (closed)
- Only explicitly allowed traffic passes

### Deep Dive: mongo-network-policy.yml

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mongo-network-policy
spec:
  podSelector:
    matchLabels:
      app: mongo
```

**podSelector**
- Which pods this policy applies to
- **Empty selector** `{}` = All pods in namespace
- **With labels** = Only matching pods

```yaml
policyTypes:
  - Ingress
  - Egress
```

**policyTypes**
- **Ingress** = Incoming traffic rules
- **Egress** = Outgoing traffic rules
- **Both** = Complete isolation (recommended)

```yaml
ingress:
  - from:
      - podSelector:
          matchLabels:
            app: backend
    ports:
      - protocol: TCP
        port: 27017
```

**ingress.from**
- Who can send traffic to mongo pods
- **podSelector** = Pods with label `app: backend`
- **Multiple selectors** = OR logic

**ports**
- Which ports are allowed
- **port: 27017** = MongoDB port
- **No ports specified** = All ports allowed

**Rule interpretation:**
```
Allow TCP traffic on port 27017
FROM pods with label app=backend
TO pods with label app=mongo
```

```yaml
egress:
  - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
```

**egress.to**
- Where mongo pods can send traffic
- **namespaceSelector: {}** = Any namespace
- **podSelector** = kube-dns pods

**Why allow DNS?**
- Pods need DNS to resolve service names
- **Without this:** Can't resolve `backend-service` to IP
- **Port 53** = DNS port

```yaml
- to:
    - podSelector:
        matchLabels:
          app: mongo
  ports:
    - protocol: TCP
      port: 27017
```

**Allow mongo-to-mongo:**
- **Why?** MongoDB replica set communication
- mongo-0 needs to talk to mongo-1
- **Without this:** Replica set breaks

### Deep Dive: backend-network-policy.yml

```yaml
ingress:
  - from:
      - podSelector:
          matchLabels:
            app: frontend
    ports:
      - protocol: TCP
        port: 5000
  - from:
      - namespaceSelector: {}
    ports:
      - protocol: TCP
        port: 5000
```

**Multiple ingress rules:**
1. Allow from frontend pods
2. Allow from any namespace (for Ingress controller)

**Why second rule?**
- Ingress controller runs in different namespace (`kube-system`)
- **Without this:** ALB can't reach backend pods

```yaml
egress:
  - to:
      - podSelector:
          matchLabels:
            app: mongo
    ports:
      - protocol: TCP
        port: 27017
```

**Allow backend → mongo:**
- Backend needs to query database
- Only port 27017 (MongoDB)

```yaml
- to:
    - namespaceSelector: {}
  ports:
    - protocol: TCP
      port: 443
```

**Allow HTTPS egress:**
- **Why?** Backend might call external APIs
- **Port 443** = HTTPS
- **Example:** Payment gateway, email service

### Selector Logic

**AND logic (both must match):**
```yaml
- from:
    - namespaceSelector:
        matchLabels:
          env: prod
      podSelector:
        matchLabels:
          app: frontend
```
**Meaning:** Pods with `app=frontend` AND in namespace with `env=prod`

**OR logic (either matches):**
```yaml
- from:
    - namespaceSelector:
        matchLabels:
          env: prod
    - podSelector:
        matchLabels:
          app: frontend
```
**Meaning:** Pods with `app=frontend` OR in namespace with `env=prod`

### Network Policy Enforcement

**Requires CNI plugin support:**
- ✅ Calico
- ✅ Cilium
- ✅ Weave Net
- ❌ Flannel (doesn't support NetworkPolicy)

**AWS VPC CNI:**
- Supports NetworkPolicy with Calico overlay
- Install: `kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml`

### Testing Network Policies

**Test connectivity:**
```bash
# From frontend pod, try to reach mongo (should fail)
kubectl exec -it frontend-pod -- curl mongo-service:27017
# Expected: Connection refused or timeout

# From backend pod, try to reach mongo (should succeed)
kubectl exec -it backend-pod -- curl mongo-service:27017
# Expected: MongoDB response
```

### Best Practices

✅ Start with deny-all, then allow specific traffic
✅ Use both Ingress and Egress policies
✅ Allow DNS (port 53) in egress
✅ Test policies before applying to production
✅ Document why each rule exists
❌ Don't use empty podSelector (affects all pods)
❌ Don't forget to allow health checks
❌ Don't block metrics collection (Prometheus)


---

## 10. Kustomization

**File:** `kustomization.yaml`

### What is Kustomize?

Kustomize is a template-free way to customize Kubernetes manifests. It's built into kubectl (kubectl apply -k).

### Why is it needed?

**Problem:** Managing multiple environments
```
dev/frontend.yml:   image: frontend:dev
staging/frontend.yml: image: frontend:staging
prod/frontend.yml:  image: frontend:v1.2.3

# 3 copies of same file! Hard to maintain!
```

**Solution:** Kustomize overlays
```
base/frontend.yml:  image: frontend  # Base template
overlays/dev/kustomization.yaml:  newTag: dev
overlays/prod/kustomization.yaml: newTag: v1.2.3

# One base, multiple overlays!
```

### Deep Dive

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
```

**apiVersion: kustomize.config.k8s.io/v1beta1**
- Kustomize API version
- **v1beta1** = Stable, widely used

**kind: Kustomization**
- Special resource type
- Not applied to cluster (used by kustomize build)

```yaml
resources:
  - storage-class.yml
  - mongo-sealedsecret.yml
  - backend-sealedsecret.yml
  - mongo-sts.yml
  - mongo-service.yml
  - backend-config.yml
  - backend.yml
  - backend-service.yml
  - frontend-config.yml
  - frontend.yml
  - frontend-service.yml
  - ingress.yml
  - frontend-hpa.yml
  - backend-hpa.yml
  - frontend-network-policy.yml
  - backend-network-policy.yml
  - mongo-network-policy.yml
```

**resources**
- List of YAML files to include
- **Order matters** for dependencies
- **Example:** Create namespace before resources in it

**Why list all files?**
- Explicit is better than implicit
- Easy to see what's included
- Can comment out files to disable

```yaml
images:
  - name: blog-site-frontend
    newName: abhi00shek/blog-site-frontend
    newTag: latest
  - name: blog-site-backend
    newName: abhi00shek/blog-site-backend
    newTag: latest
```

**images**
- **Declarative image management**
- Transforms image references in manifests

**How it works:**

**Before kustomize build:**
```yaml
# frontend.yml
containers:
  - name: frontend
    image: blog-site-frontend
```

**After kustomize build:**
```yaml
# Generated manifest
containers:
  - name: frontend
    image: abhi00shek/blog-site-frontend:latest
```

**name: blog-site-frontend**
- Image name to match in manifests
- **Matches:** `image: blog-site-frontend`
- **Doesn't match:** `image: frontend` or `image: my-frontend`

**newName: abhi00shek/blog-site-frontend**
- Full image name with registry/username
- **Format:** `[registry/]username/image`
- **Examples:**
  - `docker.io/abhi00shek/blog-site-frontend`
  - `gcr.io/project/frontend`
  - `123456.dkr.ecr.us-east-1.amazonaws.com/frontend`

**newTag: latest**
- Image tag to use
- **Updated by CI/CD:** `kustomize edit set image blog-site-frontend=....:v1-abc123`

### Kustomize Commands

**Build (generate final YAML):**
```bash
kustomize build kubernetes-manifests/
# or
kubectl kustomize kubernetes-manifests/
```

**Apply directly:**
```bash
kubectl apply -k kubernetes-manifests/
```

**Update image tag:**
```bash
cd kubernetes-manifests
kustomize edit set image blog-site-frontend=abhi00shek/blog-site-frontend:v1-abc123
```

**What this does:**
```yaml
# Before
images:
  - name: blog-site-frontend
    newName: abhi00shek/blog-site-frontend
    newTag: latest

# After
images:
  - name: blog-site-frontend
    newName: abhi00shek/blog-site-frontend
    newTag: v1-abc123
```

### Advanced Kustomize Features

**1. Common Labels:**
```yaml
commonLabels:
  app: blog-site
  env: production
```
- Adds labels to all resources
- **Use case:** Grouping, filtering

**2. Name Prefix/Suffix:**
```yaml
namePrefix: prod-
nameSuffix: -v2
```
- **Result:** `frontend-deployment` → `prod-frontend-deployment-v2`
- **Use case:** Multiple deployments in same namespace

**3. Namespace:**
```yaml
namespace: production
```
- Sets namespace for all resources
- **Overrides** namespace in individual files

**4. ConfigMap/Secret Generators:**
```yaml
configMapGenerator:
  - name: backend-config
    literals:
      - PORT=5000
      - NODE_ENV=production
```
- Generates ConfigMap from literals
- **Advantage:** Hash suffix for immutability

**5. Patches:**
```yaml
patches:
  - target:
      kind: Deployment
      name: frontend-deployment
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 5
```
- JSON Patch or Strategic Merge Patch
- **Use case:** Environment-specific changes

**6. Replacements:**
```yaml
replacements:
  - source:
      kind: ConfigMap
      name: app-config
      fieldPath: data.version
    targets:
      - select:
          kind: Deployment
        fieldPaths:
          - spec.template.metadata.labels.version
```
- Replace values from one resource to another
- **Use case:** Propagate version across resources

### Kustomize vs Helm

| Feature | Kustomize | Helm |
|---------|-----------|------|
| Templating | No (overlays) | Yes (Go templates) |
| Learning curve | Low | Medium |
| Complexity | Simple | Complex |
| Package management | No | Yes (charts) |
| Built into kubectl | Yes | No (separate tool) |
| Use case | Simple customization | Complex apps |

**When to use Kustomize:**
- ✅ Simple apps
- ✅ GitOps workflows
- ✅ Want to avoid templating
- ✅ Native kubectl integration

**When to use Helm:**
- ✅ Complex apps with many options
- ✅ Need package management
- ✅ Reusable charts
- ✅ Community charts (Prometheus, etc.)

### Kustomize in CI/CD

**Our pipeline uses Kustomize:**
```yaml
# CI/CD job
- name: Update image tag
  run: |
    cd kubernetes-manifests
    kustomize edit set image \
      blog-site-frontend=${{ secrets.DOCKER_USERNAME }}/blog-site-frontend:v1-abc123
    
- name: Commit changes
  run: |
    git add kustomization.yaml
    git commit -m "Update image tag"
    git push
```

**Why this approach?**
- ✅ Declarative (Git is source of truth)
- ✅ Auditable (Git history)
- ✅ Rollback-friendly (git revert)
- ✅ No manual updates

### ArgoCD + Kustomize

**ArgoCD natively supports Kustomize:**
```yaml
# ArgoCD Application
source:
  path: kubernetes-manifests
  kustomize:
    version: v5.0.0
```

**ArgoCD automatically:**
1. Runs `kustomize build`
2. Compares with cluster state
3. Shows diff in UI
4. Applies changes

### Best Practices

✅ Use `images` for image management (not patches)
✅ Keep base manifests simple
✅ Use overlays for environment differences
✅ Version kustomize in CI/CD
✅ Test with `kustomize build` before applying
❌ Don't use complex patches (hard to maintain)
❌ Don't mix Kustomize and Helm in same directory
❌ Don't commit generated YAML (commit kustomization.yaml)

---

## Summary: How Everything Works Together

### Application Flow

```
┌─────────────────────────────────────────────────────────────┐
│  1. User visits http://blogsite.duckdns.org                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  2. DNS resolves to ALB                                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  3. ALB (created by Ingress)                                 │
│     - Checks Ingress rules                                   │
│     - Path / → frontend-service                              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  4. frontend-service (ClusterIP)                             │
│     - Load balances to frontend pods                         │
│     - Network Policy allows traffic                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  5. frontend pod (Deployment)                                │
│     - Readiness probe passed (in Service)                    │
│     - Liveness probe passed (pod healthy)                    │
│     - Resource limits enforced                               │
│     - HPA monitors CPU/memory                                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  6. User clicks "View Blogs"                                 │
│     - Frontend calls backend API                             │
│     - URL: http://backend-service:5000/api/blogs            │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  7. backend-service (ClusterIP)                              │
│     - Load balances to backend pods                          │
│     - Network Policy allows from frontend                    │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  8. backend pod (Deployment)                                 │
│     - Reads config from ConfigMap                            │
│     - Reads secrets from SealedSecret                        │
│     - Health check endpoint /api/health                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  9. Backend connects to MongoDB                              │
│     - URL: mongodb://mongo-service:27017                    │
│     - Network Policy allows backend → mongo                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  10. mongo-service (Headless)                                │
│      - Returns pod IPs directly                              │
│      - mongo-0.mongo-service, mongo-1.mongo-service         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  11. mongo pod (StatefulSet)                                 │
│      - Reads credentials from SealedSecret                   │
│      - Data stored in PersistentVolume (EBS)                │
│      - StorageClass provisions volume                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  12. Data returned to user                                   │
│      mongo → backend → frontend → ALB → user                │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Flow (GitOps)

```
┌─────────────────────────────────────────────────────────────┐
│  1. Developer pushes code                                    │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  2. GitHub Actions CI/CD                                     │
│     - Build Docker image                                     │
│     - Tag: v1-abc123                                        │
│     - Push to Docker Hub                                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  3. CI/CD updates kustomization.yaml                         │
│     - kustomize edit set image ....:v1-abc123               │
│     - git commit && git push                                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  4. ArgoCD detects Git change                                │
│     - Polls every 3 minutes                                  │
│     - Sees kustomization.yaml updated                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  5. ArgoCD syncs                                             │
│     - Runs: kustomize build                                  │
│     - Compares with cluster                                  │
│     - Applies changes                                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  6. Kubernetes rolling update                                │
│     - Create new pod with v1-abc123                         │
│     - Wait for readiness probe                               │
│     - Add to Service                                         │
│     - Remove old pod                                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  7. New version running!                                     │
│     - Zero downtime                                          │
│     - Automatic rollback if health checks fail               │
└─────────────────────────────────────────────────────────────┘
```

### Scaling Flow (HPA)

```
┌─────────────────────────────────────────────────────────────┐
│  1. Traffic increases                                        │
│     - CPU usage: 85% (target: 70%)                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  2. HPA calculates                                           │
│     - desiredReplicas = ceil(2 × (85/70)) = 3               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  3. HPA updates Deployment                                   │
│     - spec.replicas: 2 → 3                                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Deployment creates new pod                               │
│     - Scheduler finds node with resources                    │
│     - Pulls image                                            │
│     - Starts container                                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Pod becomes ready                                        │
│     - Readiness probe passes                                 │
│     - Added to Service endpoints                             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  6. Load distributed                                         │
│     - 3 pods now handle traffic                              │
│     - CPU usage drops to ~57%                                │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Takeaways

### Resource Relationships

```
Kustomization
    ├─ Manages → All Resources
    └─ Transforms → Image names

StorageClass
    └─ Provisions → PersistentVolumes

SealedSecret
    └─ Decrypts to → Secret

StatefulSet
    ├─ Creates → Pods (ordered)
    ├─ Creates → PersistentVolumeClaims
    └─ Uses → Headless Service

Deployment
    ├─ Creates → ReplicaSet
    ├─ Uses → ConfigMap
    ├─ Uses → Secret
    └─ Managed by → HPA

Service
    ├─ Routes to → Pods (via selector)
    └─ Used by → Ingress

Ingress
    ├─ Creates → ALB
    └─ Routes to → Services

HPA
    ├─ Scales → Deployment
    └─ Reads → Metrics Server

NetworkPolicy
    └─ Filters → Pod traffic
```

### Best Practices Summary

**Security:**
- ✅ Use SealedSecrets for sensitive data
- ✅ Encrypt storage (StorageClass)
- ✅ Use NetworkPolicies
- ✅ Set resource limits
- ✅ Use non-root containers

**Reliability:**
- ✅ Set replicas ≥ 2
- ✅ Use anti-affinity
- ✅ Configure health probes
- ✅ Use rolling updates
- ✅ Set PDB (PodDisruptionBudget)

**Performance:**
- ✅ Use HPA for auto-scaling
- ✅ Set appropriate resource requests
- ✅ Use gp3 storage
- ✅ Enable caching
- ✅ Use CDN for static assets

**Operations:**
- ✅ Use GitOps (ArgoCD)
- ✅ Use Kustomize for image management
- ✅ Monitor with Prometheus
- ✅ Centralized logging
- ✅ Regular backups

---

## Further Learning

### Official Documentation
- [Kubernetes Docs](https://kubernetes.io/docs/)
- [Kustomize Docs](https://kustomize.io/)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)

### Hands-on Practice
- [Kubernetes By Example](https://kubernetesbyexample.com/)
- [Play with Kubernetes](https://labs.play-with-k8s.com/)
- [KillerCoda Kubernetes](https://killercoda.com/kubernetes)

### Books
- "Kubernetes in Action" by Marko Lukša
- "Kubernetes Patterns" by Bilgin Ibryam
- "Production Kubernetes" by Josh Rosso

---

**You now have a deep understanding of every Kubernetes resource in this project! 🎉**

