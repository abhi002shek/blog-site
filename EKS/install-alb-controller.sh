#!/bin/bash

# AWS Load Balancer Controller Installation Script
# Run this after Terraform deployment completes

set -e

CLUSTER_NAME="blog-site-cluster"
REGION="ap-south-2"
NAMESPACE="kube-system"
SERVICE_ACCOUNT_NAME="aws-load-balancer-controller"

echo "🚀 Installing AWS Load Balancer Controller for EKS cluster: $CLUSTER_NAME"

# Get the Load Balancer Controller Role ARN from Terraform output
ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn)
echo "📋 Using IAM Role ARN: $ROLE_ARN"

# Get VPC ID from Terraform output
VPC_ID=$(terraform output -raw vpc_id)
echo "🌐 Using VPC ID: $VPC_ID"

# Update kubeconfig
echo "🔧 Updating kubeconfig..."
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Install cert-manager
echo "📜 Installing cert-manager..."
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.13.5/cert-manager.yaml

# Wait for cert-manager to be ready
echo "⏳ Waiting for cert-manager to be ready..."
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=120s
kubectl wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=120s

# Create service account with IAM role annotation
echo "👤 Creating service account with IAM role annotation..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: $SERVICE_ACCOUNT_NAME
  namespace: $NAMESPACE
  annotations:
    eks.amazonaws.com/role-arn: $ROLE_ARN
EOF

# Download and apply AWS Load Balancer Controller
echo "📥 Downloading AWS Load Balancer Controller manifest..."
curl -Lo v2_7_2_full.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.7.2/v2_7_2_full.yaml

# Replace cluster name and add VPC ID in the manifest
echo "✏️  Configuring controller manifest..."
sed -i.bak -e "s|your-cluster-name|$CLUSTER_NAME|" v2_7_2_full.yaml
sed -i.bak -e "s|--ingress-class=alb|--ingress-class=alb --aws-vpc-id=$VPC_ID|" v2_7_2_full.yaml

# Apply the controller
echo "🎯 Applying AWS Load Balancer Controller..."
kubectl apply -f v2_7_2_full.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for AWS Load Balancer Controller to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/aws-load-balancer-controller -n $NAMESPACE

# Verify installation
echo "✅ Verifying installation..."
kubectl get deployment -n $NAMESPACE aws-load-balancer-controller
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=aws-load-balancer-controller

echo "🎉 AWS Load Balancer Controller installation completed successfully!"
echo ""
echo "📝 Next steps:"
echo "   1. You can now create ALB Ingress resources"
echo "   2. Use 'alb' as the ingress class in your ingress manifests"
echo "   3. The controller will automatically provision Application Load Balancers"
echo ""
echo "🔍 To check controller logs:"
echo "   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=aws-load-balancer-controller"
