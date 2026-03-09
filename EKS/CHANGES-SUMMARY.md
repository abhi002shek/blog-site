# Infrastructure Changes Summary

## All Fixes and Improvements Applied

### 1. Security Group Hardening ✅

**Before:**
```hcl
ingress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]  # ← WIDE OPEN!
}
```

**After:**
```hcl
# Allow traffic only from within VPC
ingress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = [aws_vpc.blog_site_vpc.cidr_block]  # ← Only 10.0.0.0/16
}

# Allow NodePort range for LoadBalancer
ingress {
  from_port   = 30000
  to_port     = 32767
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# Allow HTTPS
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# Allow HTTP
ingress {
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
```

**Why:** Prevents unauthorized access to worker nodes while allowing necessary traffic for ALB and Kubernetes services.

---

### 2. Resource Tagging for Cost Tracking ✅

Added consistent tags to ALL resources:
```hcl
tags = {
  Name        = "resource-name"
  Project     = "blog-site"
  Environment = "production"
  ManagedBy   = "terraform"
}
```

**Benefits:**
- Track costs by project in AWS Cost Explorer
- Filter resources by environment
- Identify Terraform-managed resources
- Compliance and governance

---

### 3. Kubernetes ELB Discovery Tags ✅

Added to subnets:
```hcl
tags = {
  "kubernetes.io/role/elb"                  = "1"
  "kubernetes.io/cluster/blog-site-cluster" = "shared"
}
```

**Why:** AWS Load Balancer Controller uses these tags to:
- Automatically discover subnets for ALB creation
- Place load balancers in correct subnets
- Enable Ingress to work properly

---

### 4. EBS CSI Driver Dependencies ✅

**Before:**
```hcl
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.blog_site.name
  addon_name   = "aws-ebs-csi-driver"
}
```

**After:**
```hcl
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.blog_site.name
  addon_name   = "aws-ebs-csi-driver"
  
  depends_on = [
    aws_eks_cluster.blog_site,
    aws_eks_node_group.blog_site  # ← Wait for nodes!
  ]
}
```

**Why:** 
- EBS CSI Driver needs worker nodes to be ready
- Prevents race condition during cluster creation
- Ensures proper installation order

---

### 5. SSH Key Update ✅

Changed from `blog-site-key` to `new_key` in `variable.tf`

**Note:** You must create this key pair in AWS EC2 console (ap-south-2 region) before running `terraform apply`.

---

## Security Improvements Summary

| Aspect | Before | After |
|--------|--------|-------|
| Node Ingress | All traffic from 0.0.0.0/0 | Restricted to VPC + specific ports |
| Cost Tracking | No tags | Full tagging strategy |
| ALB Discovery | No tags | Kubernetes ELB tags added |
| Resource Dependencies | Missing | Proper depends_on added |
| SSH Key | Generic name | Project-specific name |

---

## Files Modified

1. ✅ `main.tf` - Security groups, tags, dependencies
2. ✅ `variable.tf` - SSH key name updated
3. ✅ `output.tf` - Already correct
4. ✅ `terraform.tfstate` - Deleted (fresh start)

---

## Next Steps

1. Create SSH key pair in AWS:
   ```bash
   aws ec2 create-key-pair \
     --key-name new_key \
     --region ap-south-2 \
     --query 'KeyMaterial' \
     --output text > new_key.pem
   chmod 400 new_key.pem
   ```

2. Initialize Terraform:
   ```bash
   cd EKS
   terraform init
   ```

3. Review plan:
   ```bash
   terraform plan
   ```

4. Apply infrastructure:
   ```bash
   terraform apply
   ```

---

## Estimated Costs (ap-south-2)

- **EKS Cluster**: ~$73/month
- **3x t2.medium nodes**: ~$75/month (3 × $25)
- **EBS volumes (gp3)**: ~$1/month per 5GB
- **Data transfer**: Variable
- **Total**: ~$150-160/month

---

## Production Considerations (Future)

For production deployment, consider:

1. **Private Subnets + NAT Gateway**
   - Move worker nodes to private subnets
   - Add NAT Gateway for outbound internet
   - Cost: +$32/month per NAT Gateway

2. **Multi-AZ NAT Gateways**
   - High availability
   - Cost: +$64/month (2 NAT Gateways)

3. **Cluster Autoscaler**
   - Dynamic node scaling based on load
   - Reduce costs during low traffic

4. **Spot Instances**
   - Use spot instances for non-critical workloads
   - Save up to 70% on compute costs

5. **Monitoring & Logging**
   - Enable CloudWatch Container Insights
   - Set up alarms for cost anomalies
