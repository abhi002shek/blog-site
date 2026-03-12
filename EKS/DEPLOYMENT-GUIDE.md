# EKS Deployment Guide with AWS Load Balancer Controller

This guide provides complete instructions for deploying the EKS cluster with AWS Load Balancer Controller support.

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform installed
- kubectl installed
- SSH key pair created in AWS (update `variable.tf` with your key name)

## Deployment Steps

### 1. Deploy Infrastructure with Terraform

```bash
# Navigate to EKS directory
cd EKS

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### 2. Install AWS Load Balancer Controller

After Terraform completes successfully, run the post-deployment script:

```bash
# Make the script executable
chmod +x install-alb-controller.sh

# Run the installation script
./install-alb-controller.sh
```

### 3. Verify Installation

Check that everything is working:

```bash
# Verify cluster nodes
kubectl get nodes

# Verify AWS Load Balancer Controller
kubectl get deployment -n kube-system aws-load-balancer-controller

# Check controller pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## What's Included

### Infrastructure Components

- **VPC**: Custom VPC with proper CIDR (10.0.0.0/16)
- **Subnets**: 2 public subnets across different AZs with ELB tags
- **EKS Cluster**: Managed Kubernetes cluster
- **Node Group**: 3 t3.medium instances
- **Security Groups**: Properly configured for ALB traffic
- **IAM Roles**: All required roles and policies for EKS and ALB controller

### AWS Load Balancer Controller

- **OIDC Provider**: For IAM roles for service accounts (IRSA)
- **IAM Role**: Dedicated role for the Load Balancer Controller
- **IAM Policy**: Complete policy with all required permissions
- **Service Account**: Kubernetes service account with IAM role annotation
- **Controller Deployment**: Latest version (v2.7.2) with proper configuration

### Key Features

1. **Automatic Subnet Tagging**: Subnets are properly tagged for ELB usage
2. **VPC ID Configuration**: Controller configured with explicit VPC ID
3. **IRSA Support**: Uses IAM roles for service accounts for secure access
4. **Cert-manager Integration**: Automatic TLS certificate management
5. **Health Checks**: Proper health check configuration

## Subnet Tags Explained

The Terraform script automatically adds these required tags to subnets:

```hcl
tags = {
  "kubernetes.io/role/elb"                  = "1"           # For public ALBs
  "kubernetes.io/cluster/blog-site-cluster" = "shared"      # Cluster association
}
```

These tags tell the AWS Load Balancer Controller:
- Which subnets to use for load balancers
- That the subnets are shared between multiple clusters (if needed)

## Troubleshooting

### Controller Not Starting

If the controller fails to start, check:

```bash
# Check pod events
kubectl describe pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Common Issues

1. **VPC ID Error**: The script automatically configures VPC ID from Terraform output
2. **IAM Permissions**: All required permissions are included in the Terraform policy
3. **Subnet Tags**: Automatically applied by Terraform
4. **OIDC Provider**: Created automatically by Terraform

### Manual Verification

Verify the setup manually:

```bash
# Check subnet tags
aws ec2 describe-subnets --region ap-south-2 --filters "Name=tag:Name,Values=blog-site-subnet-*" --query 'Subnets[*].[SubnetId,Tags]'

# Check OIDC provider
aws iam list-open-id-connect-providers

# Check IAM role
aws iam get-role --role-name AmazonEKSLoadBalancerControllerRole-blog-site
```

## Next Steps

After successful deployment:

1. Deploy your applications with ALB Ingress
2. Use `alb` as the ingress class
3. The controller will automatically create Application Load Balancers
4. Monitor controller logs for any issues

## Clean Up

To destroy all resources:

```bash
# Delete the controller first
kubectl delete -f v2_7_2_full.yaml
kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.13.5/cert-manager.yaml

# Then destroy Terraform resources
terraform destroy
```
