# SQL Server 2022 on EKS - Helm Deployment

## Required AWS Services

| Service | Purpose |
|---------|---------|
| EKS | Kubernetes cluster |
| EBS CSI Driver | Dynamic volume provisioning (gp3) |
| Secrets Manager | Stores SA password |
| IAM (IRSA) | Pod-level AWS authentication |
| Secrets Store CSI Driver + ASCP | Optional (if using CSI-based secret mount) |

## Complete Setup from Scratch

### Step 1: Associate OIDC Provider

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster expense --region us-east-1 --approve
```

### Step 2: Install EBS CSI Driver

```bash
eksctl create addon --name aws-ebs-csi-driver \
  --cluster expense --region us-east-1

# Verify
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

### Step 3: Install Secrets Store CSI Driver + AWS Provider

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm repo update

helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system --set syncSecret.enabled=true

helm install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws \
  -n kube-system

# Verify
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl get pods -n kube-system -l app=secrets-store-csi-driver-provider-aws
```

### Step 4: Create Secret in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name mssql/sa-password \
  --secret-string '{"username":"sa","password":"YourStr0ng!P@ssword"}' \
  --region us-east-1
```

### Step 5: Create IRSA Role

```bash
OIDC_ID=$(aws eks describe-cluster --name expense --region us-east-1 \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|.*/||')

# Create policy
cat > /tmp/mssql-secrets-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
    "Resource": "arn:aws:secretsmanager:us-east-1:856678556116:secret:mssql/*"
  }]
}
EOF
aws iam create-policy --policy-name mssql-secrets-policy \
  --policy-document file:///tmp/mssql-secrets-policy.json

# Create role with OIDC trust
cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::856678556116:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:mssql:mssql-sa",
        "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF
aws iam create-role --role-name mssql-secrets-role \
  --assume-role-policy-document file:///tmp/trust-policy.json
aws iam attach-role-policy --role-name mssql-secrets-role \
  --policy-arn arn:aws:iam::856678556116:policy/mssql-secrets-policy

# Verify
aws iam get-role --role-name mssql-secrets-role --query "Role.Arn" --output text
```

### Step 6: Deploy with Helm

```bash
helm install mssql ./helm/mssql -n mssql --create-namespace
kubectl get pods -n mssql -w
```

### Step 7: Verify

```bash
kubectl get pods -n mssql          # Should be Running
kubectl get pvc -n mssql           # Should be Bound
kubectl logs mssql-mssql-0 -n mssql -c mssql
kubectl get svc -n mssql           # NLB endpoint
```

## Connect

```bash
# Get NLB DNS
kubectl get svc mssql-mssql -n mssql -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Connect
sqlcmd -S <nlb-dns>,1433 -U sa
```

## Allow App Namespace Access

```bash
kubectl label namespace expense access-mssql=true
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `fetch-secrets` AccessDenied | IRSA role missing | Run Step 5, then `kubectl delete pod mssql-mssql-0 -n mssql` |
| Pod ContainerCreating + volume error | CSI driver not installed | Run Step 3 |
| PVC Pending | EBS CSI driver missing | Run Step 2 |
| Pod Pending (no nodes) | Toleration mismatch | `kubectl taint nodes <node> database=mssql:NoSchedule` or remove toleration from values.yaml |
