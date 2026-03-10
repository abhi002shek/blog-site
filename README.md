# Blog-Site - Complete Deployment Guide for Linux

A full-stack blog application with React frontend, Node.js backend, and MongoDB database, deployed on AWS EKS with automated CI/CD.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                    DuckDNS Domain
                  (blogsite.duckdns.org)
                         │
                         ▼
              ┌──────────────────────┐
              │  AWS Load Balancer   │
              │       (ALB)          │
              └──────────┬───────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌─────────────────┐            ┌─────────────────┐
│   Frontend      │            │    Backend      │
│   (React)       │───────────▶│   (Node.js)     │
│   Port: 80      │            │   Port: 5000    │
└─────────────────┘            └────────┬────────┘
                                        │
                                        ▼
                               ┌─────────────────┐
                               │    MongoDB      │
                               │  StatefulSet    │
                               │   Port: 27017   │
                               └────────┬────────┘
                                        │
                                        ▼
                               ┌─────────────────┐
                               │   EBS Volume    │
                               │  (Persistent)   │
                               └─────────────────┘
```

---

## Prerequisites (Linux System)

### 1. Install Required Tools

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
terraform --version

# Install Docker
sudo apt install docker.io -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker

# Install kubeseal
KUBESEAL_VERSION='0.35.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
rm kubeseal kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz
```

**Why these tools?**
- **AWS CLI**: Interact with AWS services
- **kubectl**: Manage Kubernetes clusters
- **eksctl**: Create and manage EKS clusters easily
- **Helm**: Package manager for Kubernetes
- **Terraform**: Infrastructure as Code (IaC) for EKS
- **Docker**: Build container images
- **kubeseal**: Encrypt Kubernetes secrets

### 2. Configure AWS Credentials

```bash
aws configure
```

Enter:
- AWS Access Key ID
- AWS Secret Access Key
- Default region: `ap-south-2` (or your preferred region)
- Default output format: `json`

**Why?** All AWS CLI and eksctl commands need authentication.

### 3. Get a Free Domain

Go to https://www.duckdns.org and create a subdomain (e.g., `yourblog.duckdns.org`)

**Why?** You need a domain name to access your application. DuckDNS provides free subdomains.

---

## Part 1: Create EKS Cluster with Terraform

### Step 1: Update Terraform Configuration

Navigate to the `EKS` directory and review `main.tf`. The EBS CSI addon is commented out because it requires OIDC provider setup first.

```bash
cd EKS
```

**Important**: The `main.tf` file has the EBS CSI addon commented out:
```hcl
# EBS CSI Driver - Install manually after cluster creation
# Requires OIDC provider and IAM role
```

**Why?** The EBS CSI addon needs an OIDC provider and IAM role with proper permissions. Installing it via Terraform without these causes a 20-minute timeout. We'll install it manually after the cluster is created.

### Step 2: Initialize and Apply Terraform

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

**What this does:**
- Creates VPC with 2 public subnets across 2 availability zones
- Creates EKS cluster control plane
- Creates node group with 3 t3.medium instances
- Sets up security groups and IAM roles
- **Does NOT install EBS CSI addon** (we'll do this manually)

**Time**: ~15-20 minutes

### Step 3: Configure kubectl

```bash
aws eks update-kubeconfig --region ap-south-2 --name blog-site-cluster
```

**What this does:** Downloads cluster credentials and updates `~/.kube/config` so kubectl can communicate with your cluster.

**Verify:**
```bash
kubectl get nodes
```

You should see 3 nodes in `Ready` status.

---

## Part 2: Install Required Kubernetes Components

### Step 4: Enable OIDC Provider

**Why?** OIDC (OpenID Connect) allows Kubernetes service accounts to assume IAM roles securely. This is required for EBS CSI driver and Load Balancer Controller to access AWS APIs.

```bash
eksctl utils associate-iam-oidc-provider \
  --region ap-south-2 \
  --cluster blog-site-cluster \
  --approve
```

**What this does:** Creates an IAM OIDC identity provider for your cluster, enabling IRSA (IAM Roles for Service Accounts).

### Step 5: Install EBS CSI Driver

**Why?** MongoDB needs persistent storage. The EBS CSI driver allows Kubernetes to dynamically provision AWS EBS volumes for persistent volume claims.

#### 5a. Create IAM Service Account for EBS CSI

```bash
eksctl create iamserviceaccount \
  --cluster=blog-site-cluster \
  --namespace=kube-system \
  --name=ebs-csi-controller-sa \
  --attach-policy-arn=arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --override-existing-serviceaccounts \
  --region ap-south-2 \
  --approve
```

**What this does:**
- Creates a Kubernetes service account `ebs-csi-controller-sa`
- Creates an IAM role with EBS permissions
- Links them together using OIDC (IRSA)
- The CSI driver pods will use this service account to create/attach EBS volumes

#### 5b. Install EBS CSI Driver

```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.44"
```

**What this does:** Deploys the EBS CSI driver pods that manage EBS volume lifecycle.

#### 5c. Restart EBS CSI Controller

```bash
kubectl rollout restart deployment ebs-csi-controller -n kube-system
```

**Why?** Ensures the controller picks up the new service account with IAM permissions.

**Verify:**
```bash
kubectl get pods -n kube-system | grep ebs-csi
```

You should see `ebs-csi-controller` and `ebs-csi-node` pods running.

### Step 6: Install AWS Load Balancer Controller

**Why?** The Load Balancer Controller watches for Kubernetes Ingress resources and automatically creates AWS Application Load Balancers (ALBs) to route traffic to your services.

#### 6a. Download and Create IAM Policy

```bash
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.3/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

**What this does:** Creates an IAM policy with permissions to:
- Create/delete load balancers
- Manage target groups
- Modify security groups
- Describe EC2 resources (subnets, route tables, etc.)

**Note:** If the policy already exists, you'll get an error - that's fine, skip to next step.

#### 6b. Create IAM Service Account

```bash
# Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster=blog-site-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region ap-south-2 \
  --approve
```

**What this does:** Creates a service account for the Load Balancer Controller with IAM permissions to manage ALBs.

#### 6c. Install Load Balancer Controller via Helm

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=blog-site-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set vpcId=<YOUR-VPC-ID>
```

**Get your VPC ID:**
```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=blog-site-vpc" --region ap-south-2 --query 'Vpcs[0].VpcId' --output text
```

**What this does:** Deploys the controller that watches Ingress resources and creates ALBs.

**Verify:**
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

#### 6d. Tag Subnets for ALB Discovery

**Why?** The Load Balancer Controller needs to know which subnets to use for the ALB. It discovers them via tags.

```bash
# Get subnet IDs
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=blog-site-subnet-*" \
  --region ap-south-2 \
  --query 'Subnets[*].SubnetId' \
  --output text

# Tag subnets (replace with your subnet IDs)
aws ec2 create-tags \
  --region ap-south-2 \
  --resources subnet-xxxxx subnet-yyyyy \
  --tags Key=kubernetes.io/role/elb,Value=1 Key=kubernetes.io/cluster/blog-site-cluster,Value=shared
```

**What these tags mean:**
- `kubernetes.io/role/elb=1`: This subnet can be used for public load balancers
- `kubernetes.io/cluster/blog-site-cluster=shared`: This subnet belongs to this cluster

### Step 7: Install Sealed Secrets Controller

**Why?** Kubernetes secrets are only base64 encoded (not encrypted). Sealed Secrets encrypts them so you can safely store them in Git. The controller decrypts them in the cluster.

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update sealed-secrets

helm install sealed-secrets-controller sealed-secrets/sealed-secrets \
  --namespace kube-system
```

**What this does:** Deploys the Sealed Secrets controller which:
- Generates a public/private key pair
- Decrypts SealedSecret resources into regular Secrets
- Only works in this specific cluster (secrets can't be decrypted elsewhere)

**Verify:**
```bash
kubectl get pods -n kube-system | grep sealed-secrets
```

---

## Part 3: Prepare Application Secrets

### Step 8: Create Sealed Secrets

**Why?** Your MongoDB credentials need to be encrypted before storing in Git.

#### 8a. Create MongoDB Sealed Secret

```bash
cd ../kubernetes-manifests

kubectl create secret generic mongo-secrets \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=admin \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD=mongodb123 \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  -o yaml > mongo-sealedsecret.yml
```

**What this does:**
1. Creates a regular Kubernetes secret (in memory only, not applied)
2. Pipes it to kubeseal which encrypts it using the cluster's public key
3. Saves the encrypted SealedSecret to a file

**Important:** Replace `admin` and `mongodb123` with your own credentials!

#### 8b. Create Backend Sealed Secret

```bash
kubectl create secret generic backend-secrets \
  --from-literal=MONGO_URI="mongodb://admin:mongodb123@mongo-service:27017/mydb?authSource=admin" \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  -o yaml > backend-sealedsecret.yml
```

**What this does:** Encrypts the MongoDB connection string for the backend.

**Note:** Make sure the username and password match what you used in step 8a!

---

## Part 4: Build and Push Docker Images

### Step 9: Build Multi-Platform Images

**Why multi-platform?** If you build on an ARM64 machine (Apple Silicon Mac), the images won't work on EKS (which uses AMD64). Multi-platform images work on both.

#### 9a. Login to Docker Hub

```bash
docker login
```

Enter your Docker Hub username and password.

#### 9b. Set Up Buildx (if not already set up)

```bash
docker buildx create --name multibuilder --driver docker-container --bootstrap --use
```

**What this does:** Creates a builder that supports building for multiple CPU architectures.

#### 9c. Build and Push Backend Image

```bash
cd ../server

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <YOUR-DOCKERHUB-USERNAME>/blog-site-backend:v1 \
  --push .
```

**Replace `<YOUR-DOCKERHUB-USERNAME>`** with your actual Docker Hub username!

**What this does:**
- Builds the image for both AMD64 (EKS) and ARM64 (Apple Silicon)
- Creates a manifest list that serves the right architecture automatically
- Pushes to Docker Hub

#### 9d. Build and Push Frontend Image

```bash
cd ../frontend

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <YOUR-DOCKERHUB-USERNAME>/blog-site-frontend:v1 \
  --push .
```

#### 9e. Update Kubernetes Manifests with Your Images

Edit the deployment files to use your Docker Hub username:

```bash
cd ../kubernetes-manifests

# Update backend deployment
sed -i 's|abhi00shek/blog-site-backend:v1|<YOUR-DOCKERHUB-USERNAME>/blog-site-backend:v1|g' backend.yml

# Update frontend deployment
sed -i 's|abhi00shek/blog-site-frontend:v1|<YOUR-DOCKERHUB-USERNAME>/blog-site-frontend:v1|g' frontend.yml
```

**Or manually edit** `backend.yml` and `frontend.yml` to change the image names.

---

## Part 5: Deploy Application to Kubernetes

### Step 10: Update Ingress with Your Domain

Edit `ingress.yml` and replace `blogsite.duckdns.org` with your DuckDNS domain:

```bash
sed -i 's|blogsite.duckdns.org|<YOUR-DOMAIN>.duckdns.org|g' ingress.yml
```

### Step 11: Deploy All Components

```bash
# Deploy storage class (defines how to provision EBS volumes)
kubectl apply -f storage-class.yml

# Deploy sealed secrets (will be decrypted by controller)
kubectl apply -f mongo-sealedsecret.yml
kubectl apply -f backend-sealedsecret.yml

# Verify secrets were created
kubectl get secrets

# Deploy MongoDB StatefulSet with persistent storage
kubectl apply -f mongo-sts.yml
kubectl apply -f mongo-service.yml

# Wait for MongoDB to be ready
kubectl wait --for=condition=ready pod -l app=mongo --timeout=300s

# Deploy Backend
kubectl apply -f backend-config.yml
kubectl apply -f backend.yml
kubectl apply -f backend-service.yml

# Deploy Frontend
kubectl apply -f frontend-config.yml
kubectl apply -f frontend.yml
kubectl apply -f frontend-service.yml

# Deploy Ingress (creates ALB)
kubectl apply -f ingress.yml
```

**What each component does:**

- **storage-class.yml**: Defines how to create EBS volumes (gp3 type, encrypted)
- **mongo-sealedsecret.yml**: Encrypted MongoDB credentials
- **backend-sealedsecret.yml**: Encrypted MongoDB connection string
- **mongo-sts.yml**: MongoDB StatefulSet with persistent volume claim
- **mongo-service.yml**: Headless service for MongoDB (mongo-service:27017)
- **backend-config.yml**: Environment variables for backend
- **backend.yml**: Backend deployment (Node.js API)
- **backend-service.yml**: Service to expose backend
- **frontend-config.yml**: Environment variables for frontend
- **frontend.yml**: Frontend deployment (React app)
- **frontend-service.yml**: Service to expose frontend
- **ingress.yml**: Ingress resource (triggers ALB creation)

### Step 12: Wait for ALB to be Created

```bash
# Watch ingress until ADDRESS appears (takes 2-3 minutes)
kubectl get ingress app-ingress -w
```

Press `Ctrl+C` when you see an ADDRESS like:
```
blog-site-ingress-xxxxx.ap-south-2.elb.amazonaws.com
```

### Step 13: Point Your Domain to the ALB

#### Get ALB IP Address

```bash
ALB_DNS=$(kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ALB_IP=$(dig +short $ALB_DNS | head -1)
echo "Point your domain to: $ALB_IP"
```

#### Update DuckDNS

1. Go to https://www.duckdns.org
2. Find your domain
3. Update the IP address to the `$ALB_IP` from above
4. Click "update ip"

**Why?** This makes your domain name resolve to the AWS Load Balancer.

### Step 14: Test Your Application

Wait 1-2 minutes for DNS to propagate, then:

```bash
curl http://<YOUR-DOMAIN>.duckdns.org
```

Or open in browser: `http://<YOUR-DOMAIN>.duckdns.org`

You should see your blog application! 🎉

---

## Part 6: Verify Deployment

### Check All Pods are Running

```bash
kubectl get pods
```

Expected output:
```
NAME                                   READY   STATUS    RESTARTS   AGE
backend-xxxxx                          1/1     Running   0          5m
frontend-deployment-xxxxx              1/1     Running   0          5m
mongo-0                                1/1     Running   0          5m
mongo-1                                1/1     Running   0          5m
```

### Check Services

```bash
kubectl get svc
```

### Check Ingress

```bash
kubectl get ingress
```

### Check Persistent Volumes

```bash
kubectl get pvc
```

MongoDB PVCs should be `Bound`.

### Test Backend API

```bash
curl http://<YOUR-DOMAIN>.duckdns.org/api/blogs
```

Should return `[]` (empty array) initially.

---

## Troubleshooting

### Issue 1: Pods Stuck in Pending

**Check:**
```bash
kubectl describe pod <POD-NAME>
```

**Common causes:**
- PVC not bound → Check EBS CSI driver is running
- Insufficient resources → Check node capacity
- Image pull errors → Check image name and Docker Hub access

### Issue 2: Ingress Has No ADDRESS

**Check Load Balancer Controller logs:**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```

**Common causes:**
- Subnets not tagged → Re-run subnet tagging command
- IAM permissions missing → Check service account has correct policy
- VPC ID not set in Helm → Reinstall with `--set vpcId=<VPC-ID>`

### Issue 3: Image Pull Errors

**Check pod events:**
```bash
kubectl describe pod <POD-NAME>
```

**Common causes:**
- Wrong image name → Check Docker Hub username
- Private repository → Make images public or create image pull secret
- Platform mismatch → Rebuild with `--platform linux/amd64,linux/arm64`

### Issue 4: MongoDB Connection Errors

**Check backend logs:**
```bash
kubectl logs -l app=backend
```

**Common causes:**
- Secrets not created → Check `kubectl get secrets`
- Wrong MongoDB URI → Check backend-sealedsecret.yml
- MongoDB not ready → Check `kubectl get pods -l app=mongo`

### Issue 5: 404 Errors from ALB

**This is normal!** The ingress requires the `Host` header. Test with:
```bash
curl -H "Host: <YOUR-DOMAIN>.duckdns.org" http://<ALB-DNS>
```

If this works but the domain doesn't, check DNS propagation:
```bash
dig <YOUR-DOMAIN>.duckdns.org
```

---

## CI/CD Pipeline

The project includes a GitHub Actions workflow (`.github/workflows/cicd.yaml`) that:

1. **Security Checks**
   - Trivy filesystem scan for vulnerabilities
   - Gitleaks scan for secrets in code

2. **Code Quality**
   - SonarQube code analysis
   - Quality gate check

3. **Build & Push**
   - Detects changes in frontend/backend
   - Builds Docker images with auto-incrementing tags
   - Pushes to Docker Hub

### Setup CI/CD

1. **Add GitHub Secrets** (Settings → Secrets and variables → Actions):
   - `DOCKER_USERNAME`: Your Docker Hub username
   - `DOCKER_TOKEN`: Docker Hub access token
   - `SONAR_TOKEN`: SonarQube token

2. **Add GitHub Variables**:
   - `SONAR_HOST_URL`: Your SonarQube server URL

3. **Push to main branch** to trigger the pipeline

---

## Architecture Decisions

### Why Sealed Secrets?

**Problem:** Kubernetes secrets are base64 encoded, not encrypted. Storing them in Git is insecure.

**Solution:** Sealed Secrets encrypts secrets with a cluster-specific key. Only that cluster can decrypt them.

**Alternative:** External secret managers (AWS Secrets Manager, HashiCorp Vault) - more complex but better for production.

### Why StatefulSet for MongoDB?

**Problem:** Deployments don't guarantee stable network identity or persistent storage.

**Solution:** StatefulSets provide:
- Stable pod names (mongo-0, mongo-1)
- Persistent volume per pod
- Ordered deployment and scaling

### Why ALB Instead of NLB?

**ALB (Application Load Balancer):**
- Layer 7 (HTTP/HTTPS)
- Path-based routing (/api → backend, / → frontend)
- Host-based routing (multiple domains)
- Better for web applications

**NLB (Network Load Balancer):**
- Layer 4 (TCP/UDP)
- Higher performance
- Better for non-HTTP traffic

### Why Not Let's Encrypt SSL?

**Problem:** ALB doesn't support HTTP-01 challenges well, and DuckDNS doesn't support CNAME records needed for DNS-01 challenges.

**Solutions:**
1. Use AWS Certificate Manager (ACM) with a real domain
2. Use Cloudflare for DNS (supports CNAME)
3. Use HTTP only (current setup)

---

## Cost Estimation

**Monthly costs (ap-south-2 region):**

- EKS Control Plane: $73/month ($0.10/hour)
- EC2 Instances (3x t3.medium): ~$90/month
- EBS Volumes (2x 5GB gp3): ~$1/month
- ALB: ~$18/month
- Data Transfer: Variable

**Total: ~$180-200/month**

**Cost optimization:**
- Use t3.small instead of t3.medium: Save ~$30/month
- Use 2 nodes instead of 3: Save ~$30/month
- Use Fargate instead of EC2: Pay per pod (good for low traffic)

---

## Cleanup

To delete everything and avoid charges:

```bash
# Delete Kubernetes resources
kubectl delete -f kubernetes-manifests/

# Delete Helm releases
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall sealed-secrets-controller -n kube-system

# Delete EKS cluster
cd EKS
terraform destroy -auto-approve

# Delete IAM policy
aws iam delete-policy --policy-arn arn:aws:iam::<ACCOUNT-ID>:policy/AWSLoadBalancerControllerIAMPolicy
```

---

## Key Learnings from Deployment

### 1. EBS CSI Addon Timeout Issue

**Problem:** Installing EBS CSI addon via Terraform times out after 20 minutes.

**Root Cause:** The addon needs an OIDC provider and IAM role with proper permissions. Without these, it can't authenticate with AWS APIs.

**Solution:** 
- Comment out the addon in Terraform
- Create OIDC provider with eksctl
- Create IAM service account with proper permissions
- Install CSI driver manually

### 2. Platform Architecture Mismatch

**Problem:** Images built on Apple Silicon (ARM64) don't work on EKS (AMD64).

**Error:** `no match for platform in manifest: not found`

**Solution:** Build multi-platform images:
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t image:tag --push .
```

### 3. Subnet Discovery Failure

**Problem:** Load Balancer Controller can't find subnets.

**Error:** `couldn't auto-discover subnets: unable to resolve at least one subnet`

**Solution:** Tag subnets with:
- `kubernetes.io/role/elb=1`
- `kubernetes.io/cluster/<CLUSTER-NAME>=shared`

### 4. IAM Policy Incomplete

**Problem:** Load Balancer Controller missing `ec2:DescribeRouteTables` permission.

**Solution:** Use the latest IAM policy from AWS documentation and update existing policy:
```bash
aws iam create-policy-version --policy-arn <ARN> --policy-document file://iam_policy.json --set-as-default
```

### 5. Sealed Secrets Key Mismatch

**Problem:** Sealed secrets created on one cluster don't work on another.

**Why:** Each cluster has a unique encryption key.

**Solution:** Recreate sealed secrets after creating a new cluster using kubeseal.

---

## Additional Resources

- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Docker Multi-Platform Builds](https://docs.docker.com/build/building/multi-platform/)

---

## Support

For issues or questions:
1. Check the Troubleshooting section
2. Review pod logs: `kubectl logs <POD-NAME>`
3. Check events: `kubectl get events --sort-by='.lastTimestamp'`
4. Describe resources: `kubectl describe <RESOURCE-TYPE> <NAME>`

---

**Happy Deploying! 🚀**
