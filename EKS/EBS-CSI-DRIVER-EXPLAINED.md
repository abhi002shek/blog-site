# Why EBS CSI Driver is Required for Blog-Site Application

## The Problem Without EBS CSI Driver

Your blog-site application uses **MongoDB as a StatefulSet** with persistent storage. Without the EBS CSI driver, Kubernetes cannot dynamically provision EBS volumes for your database.

## What is EBS CSI Driver?

**CSI** = Container Storage Interface (standard for storage in Kubernetes)
**EBS** = Elastic Block Store (AWS persistent block storage)

The EBS CSI Driver is a plugin that allows Kubernetes to:
1. Dynamically create EBS volumes
2. Attach them to EC2 worker nodes
3. Mount them into pods
4. Manage their lifecycle (resize, snapshot, delete)

## Your Application's Specific Need

### MongoDB StatefulSet Configuration
Looking at your `kubernetes-manifests/mongo-sts.yml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
spec:
  volumeClaimTemplates:
  - metadata:
      name: mongo-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: mongo-storage  # ← Requires EBS CSI Driver
      resources:
        requests:
          storage: 5Gi
```

### Storage Class Configuration
Your `kubernetes-manifests/storage-class.yml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mongo-storage
provisioner: ebs.csi.aws.com  # ← This is the EBS CSI Driver
parameters:
  type: gp3  # ← AWS EBS volume type
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
```

## What Happens When MongoDB Pod Starts

### Without EBS CSI Driver:
```
1. MongoDB StatefulSet created
2. PersistentVolumeClaim (PVC) created
3. ❌ STUCK - No provisioner to create EBS volume
4. ❌ Pod stays in "Pending" state
5. ❌ Error: "waiting for a volume to be created"
```

### With EBS CSI Driver:
```
1. MongoDB StatefulSet created
2. PersistentVolumeClaim (PVC) created
3. ✅ EBS CSI Driver sees the PVC request
4. ✅ Creates a 5GB gp3 EBS volume in AWS
5. ✅ Attaches volume to the worker node
6. ✅ Mounts volume into MongoDB pod at /data/db
7. ✅ MongoDB starts and stores data persistently
```

## Why It's in Terraform

```hcl
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.blog_site.name
  addon_name   = "aws-ebs-csi-driver"
  
  depends_on = [
    aws_eks_cluster.blog_site,
    aws_eks_node_group.blog_site
  ]
}
```

**Benefits of Terraform-managed addon:**
- Automatically installed with cluster creation
- AWS manages the driver version and updates
- Integrated with IAM permissions (via node role)
- No manual kubectl installation needed

## IAM Permissions Required

Your node group role has this policy attached:

```hcl
resource "aws_iam_role_policy_attachment" "blog_site_node_group_ebs_policy" {
  role       = aws_iam_role.blog_site_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
```

This allows the EBS CSI Driver to:
- CreateVolume
- AttachVolume
- DetachVolume
- DeleteVolume
- CreateSnapshot
- DeleteSnapshot

## Real-World Scenario

### When MongoDB Pod Restarts:
1. Pod dies on node-1
2. Kubernetes schedules it on node-2
3. EBS CSI Driver:
   - Detaches EBS volume from node-1
   - Attaches same volume to node-2
   - Mounts it into new pod
4. MongoDB starts with **same data** (persistent!)

### Without EBS CSI Driver:
- MongoDB would lose all data on restart
- Blog posts, users, comments = GONE
- Application would be stateless (bad for database)

## Alternative Approaches (Why We Don't Use Them)

### 1. Manual EBS Volume Creation
- Create EBS volume manually in AWS console
- Create PersistentVolume manually in Kubernetes
- ❌ Not scalable, error-prone, no automation

### 2. HostPath Volumes
```yaml
volumes:
  - name: mongo-data
    hostPath:
      path: /data/mongo
```
- ❌ Data tied to specific node
- ❌ Lost if node dies
- ❌ Can't move between nodes

### 3. EFS (Elastic File System)
- ❌ Slower than EBS for databases
- ❌ More expensive
- ❌ Overkill for single-pod storage

## Summary

**EBS CSI Driver is required because:**

1. ✅ Your MongoDB needs persistent storage
2. ✅ StatefulSet uses dynamic volume provisioning
3. ✅ StorageClass specifies `ebs.csi.aws.com` provisioner
4. ✅ Enables automatic EBS volume lifecycle management
5. ✅ Allows data to persist across pod restarts/rescheduling
6. ✅ Production-grade storage solution for databases

**Without it:** Your blog-site database would lose all data on every restart! 💥
