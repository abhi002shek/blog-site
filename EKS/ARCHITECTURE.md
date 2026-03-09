# Blog-Site EKS Infrastructure Architecture

## AWS Resources Created by Terraform

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS Region: ap-south-2                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  VPC: blog-site-vpc (10.0.0.0/16)                                           │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  Internet Gateway: blog-site-igw                                    │    │
│  │                           │                                         │    │
│  │                           ▼                                         │    │
│  │  Route Table: blog-site-route-table                                │    │
│  │  (Routes: 0.0.0.0/0 → IGW)                                         │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌──────────────────────────────────┬──────────────────────────────────┐   │
│  │  Subnet-0 (ap-south-2a)          │  Subnet-1 (ap-south-2b)          │   │
│  │  CIDR: 10.0.0.0/24               │  CIDR: 10.0.1.0/24               │   │
│  │  Public IP: Enabled              │  Public IP: Enabled              │   │
│  │                                  │                                  │   │
│  │  ┌────────────────────────────┐  │  ┌────────────────────────────┐  │   │
│  │  │  EKS Worker Nodes          │  │  │  EKS Worker Nodes          │  │   │
│  │  │  (t2.medium)               │  │  │  (t2.medium)               │  │   │
│  │  │  - Node 1                  │  │  │  - Node 2                  │  │   │
│  │  │  - Node 3 (distributed)    │  │  │                            │  │   │
│  │  └────────────────────────────┘  │  └────────────────────────────┘  │   │
│  └──────────────────────────────────┴──────────────────────────────────┘   │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  EKS Cluster: blog-site-cluster                                    │    │
│  │  ├─ Control Plane (Managed by AWS)                                 │    │
│  │  ├─ Node Group: blog-site-node-group                               │    │
│  │  │  ├─ Min: 3 nodes                                                │    │
│  │  │  ├─ Max: 3 nodes                                                │    │
│  │  │  ├─ Desired: 3 nodes                                            │    │
│  │  │  └─ Instance Type: t2.medium                                    │    │
│  │  └─ EKS Addon: aws-ebs-csi-driver                                  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  Security Groups                                                    │    │
│  │  ┌──────────────────────────────────────────────────────────────┐  │    │
│  │  │  blog-site-cluster-sg (EKS Control Plane)                    │  │    │
│  │  │  Egress: All traffic → 0.0.0.0/0                             │  │    │
│  │  └──────────────────────────────────────────────────────────────┘  │    │
│  │  ┌──────────────────────────────────────────────────────────────┐  │    │
│  │  │  blog-site-node-sg (Worker Nodes)                            │  │    │
│  │  │  Ingress: All traffic → 0.0.0.0/0                            │  │    │
│  │  │  Egress: All traffic → 0.0.0.0/0                             │  │    │
│  │  │  SSH Access: Via blog-site-key                               │  │    │
│  │  └──────────────────────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  IAM Roles & Policies                                                        │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  blog-site-cluster-role (EKS Cluster)                              │    │
│  │  └─ Policy: AmazonEKSClusterPolicy                                 │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  blog-site-node-group-role (Worker Nodes)                          │    │
│  │  ├─ AmazonEKSWorkerNodePolicy                                      │    │
│  │  ├─ AmazonEKS_CNI_Policy                                           │    │
│  │  ├─ AmazonEC2ContainerRegistryReadOnly                             │    │
│  │  └─ AmazonEBSCSIDriverPolicy                                       │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Resource Summary

### Networking (6 resources)
1. **VPC** - blog-site-vpc (10.0.0.0/16)
2. **Subnets** - 2 public subnets across 2 AZs
3. **Internet Gateway** - blog-site-igw
4. **Route Table** - blog-site-route-table
5. **Route Table Associations** - 2 (one per subnet)
6. **Security Groups** - 2 (cluster + nodes)

### Compute (3 resources)
7. **EKS Cluster** - blog-site-cluster
8. **EKS Node Group** - blog-site-node-group (3 t2.medium instances)
9. **EKS Addon** - aws-ebs-csi-driver

### IAM (6 resources)
10. **IAM Role** - blog-site-cluster-role
11. **IAM Role** - blog-site-node-group-role
12. **IAM Policy Attachments** - 5 policies attached to roles

### Storage
13. **EBS CSI Driver** - Enables dynamic EBS volume provisioning for pods

---

**Total Resources Created: ~20 AWS resources**

## Key Features

- **Multi-AZ Deployment**: Nodes distributed across ap-south-2a and ap-south-2b
- **Public Subnets**: All nodes have public IPs for internet access
- **SSH Access**: Nodes accessible via blog-site-key SSH key
- **EBS Support**: Built-in EBS CSI driver for persistent storage
- **Scalable**: Node group configured for 3 nodes (can be adjusted)
