# Kubernetes Secrets Deep Dive - Blog-Site Application

## Current Implementation: Sealed Secrets ✅

Your application uses **Bitnami Sealed Secrets** - this is a **PRODUCTION-GRADE** approach!

### What Are Sealed Secrets?

**Problem with Regular Kubernetes Secrets:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongo-secrets
data:
  MONGO_INITDB_ROOT_PASSWORD: bW9uZ29kYjEyMw==  # ← Base64 encoded (NOT encrypted!)
```

**Issue:** Base64 is NOT encryption, it's just encoding!
```bash
echo "bW9uZ29kYjEyMw==" | base64 -d
# Output: mongodb123  ← Anyone can decode this!
```

**You CANNOT safely commit regular Secrets to Git!**

---

## How Sealed Secrets Work

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Your Workflow                            │
└─────────────────────────────────────────────────────────────────┘

1. Create regular secret (locally, never commit):
   kubectl create secret generic mongo-secrets \
     --from-literal=MONGO_INITDB_ROOT_PASSWORD=mongodb123 \
     --dry-run=client -o yaml

2. Encrypt with kubeseal (using cluster's public key):
   kubeseal --controller-name sealed-secrets-controller \
     --controller-namespace kube-system \
     -o yaml > mongo-sealedsecret.yml

3. Commit encrypted SealedSecret to Git ✅ (SAFE!)

4. Apply to cluster:
   kubectl apply -f mongo-sealedsecret.yml

5. Sealed Secrets Controller decrypts it:
   SealedSecret → Regular Secret (in cluster only)

6. Pods consume the decrypted Secret
```

### Encryption Flow

```
┌──────────────────┐
│  Plain Secret    │
│  password: abc   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐      ┌─────────────────────────┐
│   kubeseal CLI   │◄─────┤ Cluster Public Key      │
│   (Encrypts)     │      │ (Fetched from cluster)  │
└────────┬─────────┘      └─────────────────────────┘
         │
         ▼
┌──────────────────┐
│  SealedSecret    │
│  Encrypted Data  │  ← SAFE to commit to Git!
└────────┬─────────┘
         │
         │ kubectl apply
         ▼
┌──────────────────┐      ┌─────────────────────────┐
│  K8s Cluster     │      │ Sealed Secrets          │
│                  │◄─────┤ Controller              │
│                  │      │ (Has Private Key)       │
└────────┬─────────┘      └─────────────────────────┘
         │
         │ Decrypts
         ▼
┌──────────────────┐
│  Regular Secret  │
│  (In cluster)    │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   MongoDB Pod    │
│   Reads secret   │
└──────────────────┘
```

---

## Your Current Secrets

### 1. mongo-sealedsecret.yml

**Contains:**
- `MONGO_INITDB_ROOT_USERNAME` (encrypted)
- `MONGO_INITDB_ROOT_PASSWORD` (encrypted)

**Used by:** MongoDB StatefulSet
**Purpose:** Root credentials for MongoDB database

**Decrypted values (example from README):**
```bash
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=mongodb123
```

### 2. backend-sealedsecret.yml

**Contains:**
- `MONGO_URI` (encrypted)

**Used by:** Backend Deployment
**Purpose:** Connection string for backend to connect to MongoDB

**Decrypted value (example from README):**
```bash
MONGO_URI="mongodb://admin:mongodb123@mongo-service:27017/mydb?authSource=admin"
```

---

## Why Sealed Secrets is the RIGHT Choice

### ✅ Advantages

1. **Git-Safe**: Encrypted secrets can be committed to version control
2. **GitOps Ready**: Works perfectly with ArgoCD (your deployment tool)
3. **Cluster-Specific**: Secrets encrypted for one cluster can't be decrypted in another
4. **No External Dependencies**: No need for HashiCorp Vault, AWS Secrets Manager, etc.
5. **Audit Trail**: All secret changes tracked in Git
6. **Declarative**: Fits Kubernetes declarative model

### ❌ Disadvantages

1. **Key Management**: If you lose the controller's private key, you lose all secrets
2. **Rotation Complexity**: Changing secrets requires re-encryption
3. **No Secret Versioning**: Can't easily rollback to previous secret values
4. **Cluster Coupling**: Secrets tied to specific cluster

---

## Alternative Secret Management Solutions

### 1. AWS Secrets Manager + External Secrets Operator

**How it works:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mongo-secrets
spec:
  secretStoreRef:
    name: aws-secrets-manager
  target:
    name: mongo-secrets
  data:
    - secretKey: MONGO_INITDB_ROOT_PASSWORD
      remoteRef:
        key: blog-site/mongo/password
```

**Pros:**
- Centralized secret management
- Automatic rotation
- Audit logging in AWS CloudTrail
- Multi-cluster secret sharing

**Cons:**
- Additional AWS costs (~$0.40/secret/month)
- More complex setup
- External dependency

**Setup Steps:**
```bash
# 1. Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace

# 2. Create secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name blog-site/mongo/password \
  --secret-string "mongodb123" \
  --region ap-south-2

# 3. Create IAM policy for External Secrets
# 4. Create SecretStore resource
# 5. Create ExternalSecret resources
```

---

### 2. HashiCorp Vault

**How it works:**
```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: mongo-secrets
spec:
  vaultAuthRef: vault-auth
  mount: secret
  path: blog-site/mongo
  destination:
    name: mongo-secrets
```

**Pros:**
- Enterprise-grade secret management
- Dynamic secrets (auto-generated, auto-rotated)
- Fine-grained access control
- Secret versioning

**Cons:**
- Complex setup and maintenance
- Requires running Vault server
- Steep learning curve
- Overkill for small projects

---

### 3. SOPS (Secrets OPerationS)

**How it works:**
```bash
# Encrypt file with AWS KMS
sops --encrypt --kms arn:aws:kms:ap-south-2:123456:key/abc secrets.yaml > secrets.enc.yaml

# Decrypt in CI/CD
sops --decrypt secrets.enc.yaml | kubectl apply -f -
```

**Pros:**
- Simple file-based encryption
- Works with Git
- Supports multiple cloud KMS

**Cons:**
- Manual decryption in CI/CD
- Not Kubernetes-native
- No automatic sync

---

### 4. Kubernetes Native Secrets (NOT RECOMMENDED)

**How it works:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongo-secrets
type: Opaque
data:
  password: bW9uZ29kYjEyMw==  # Base64 encoded
```

**Pros:**
- Built-in, no extra tools
- Simple to use

**Cons:**
- ❌ Base64 is NOT encryption
- ❌ Cannot commit to Git safely
- ❌ Secrets visible to anyone with cluster access
- ❌ No audit trail

---

## Recommendation for Blog-Site

### Keep Sealed Secrets! ✅

**Why:**
1. You're already using it correctly
2. Perfect for GitOps with ArgoCD
3. No additional costs
4. Sufficient security for this application
5. Simple to manage

### When to Consider Alternatives:

**Use AWS Secrets Manager if:**
- You need automatic secret rotation
- You have compliance requirements (SOC2, HIPAA)
- You manage multiple clusters
- You need centralized secret management

**Use Vault if:**
- Enterprise environment
- Need dynamic database credentials
- Complex secret workflows
- Large team with role-based access

---

## How to Recreate Your Sealed Secrets

### Prerequisites

1. **Sealed Secrets Controller installed in cluster:**
```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets-controller sealed-secrets/sealed-secrets -n kube-system
```

2. **kubeseal CLI installed locally:**
```bash
KUBESEAL_VERSION='0.35.0'
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Step-by-Step: Create Mongo Secrets

```bash
# 1. Create regular secret (dry-run, don't apply)
kubectl create secret generic mongo-secrets \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=admin \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD=mongodb123 \
  --dry-run=client -o yaml > mongo-secret-temp.yaml

# 2. Encrypt with kubeseal
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  < mongo-secret-temp.yaml > mongo-sealedsecret.yml

# 3. Delete temp file (contains plain text!)
rm mongo-secret-temp.yaml

# 4. Commit encrypted file to Git
git add mongo-sealedsecret.yml
git commit -m "Add encrypted mongo secrets"
```

### Step-by-Step: Create Backend Secrets

```bash
# 1. Create regular secret
kubectl create secret generic backend-secrets \
  --from-literal=MONGO_URI="mongodb://admin:mongodb123@mongo-service:27017/mydb?authSource=admin" \
  --dry-run=client -o yaml > backend-secret-temp.yaml

# 2. Encrypt with kubeseal
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  < backend-secret-temp.yaml > backend-sealedsecret.yml

# 3. Delete temp file
rm backend-secret-temp.yaml

# 4. Commit to Git
git add backend-sealedsecret.yml
git commit -m "Add encrypted backend secrets"
```

---

## Secret Rotation Process

### When to Rotate:
- Security breach suspected
- Employee with access leaves
- Regular security policy (every 90 days)
- Compliance requirements

### How to Rotate:

```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# 2. Create new sealed secret
kubectl create secret generic mongo-secrets \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=admin \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD=$NEW_PASSWORD \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml > mongo-sealedsecret.yml

# 3. Update backend secret with new password
kubectl create secret generic backend-secrets \
  --from-literal=MONGO_URI="mongodb://admin:$NEW_PASSWORD@mongo-service:27017/mydb?authSource=admin" \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml > backend-sealedsecret.yml

# 4. Apply changes
kubectl apply -f mongo-sealedsecret.yml
kubectl apply -f backend-sealedsecret.yml

# 5. Restart pods to pick up new secrets
kubectl rollout restart statefulset/mongo
kubectl rollout restart deployment/backend
```

---

## Security Best Practices

### ✅ DO:
- Use Sealed Secrets for GitOps workflows
- Rotate secrets regularly
- Backup sealed-secrets controller private key
- Use strong, random passwords
- Limit RBAC access to secrets
- Enable audit logging

### ❌ DON'T:
- Commit plain Kubernetes Secrets to Git
- Use weak passwords (like "mongodb123" in production!)
- Share secrets via Slack/email
- Hardcode secrets in application code
- Use same secrets across environments

---

## Backup & Disaster Recovery

### Backup Sealed Secrets Controller Key

**CRITICAL:** If you lose this key, you lose all secrets!

```bash
# Backup the controller's private key
kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml

# Store this file SECURELY:
# - Encrypted USB drive
# - Password manager (1Password, LastPass)
# - AWS S3 with encryption
# - DO NOT commit to Git!
```

### Restore Process

```bash
# If you need to restore the key to a new cluster
kubectl apply -f sealed-secrets-key-backup.yaml -n kube-system

# Restart sealed-secrets controller
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system
```

---

## Summary

**Your current implementation is EXCELLENT! ✅**

- ✅ Using Sealed Secrets (production-grade)
- ✅ Secrets encrypted and safe to commit
- ✅ Works perfectly with ArgoCD
- ✅ No additional costs
- ✅ Simple to manage

**No changes needed unless:**
- You need automatic rotation → Consider AWS Secrets Manager
- You have compliance requirements → Consider Vault
- You manage 10+ clusters → Consider centralized solution

**For blog-site application: Keep Sealed Secrets!**
