#!/bin/bash
# AWS Setup for SQL Server Secrets Manager Integration
# Run this BEFORE deploying the Kubernetes manifests

CLUSTER_NAME="expense"
REGION="us-east-1"
ACCOUNT_ID="856678556116"
NAMESPACE="mssql"
SA_NAME="mssql-sa"
ROLE_NAME="mssql-secrets-role"

# Step 1: Create secret in AWS Secrets Manager (skip if already exists)
aws secretsmanager create-secret \
  --name mssql/sa-password \
  --secret-string '{"username":"sa","password":"MyStr0ng!P@ss2024"}' \
  --region $REGION 2>/dev/null || echo "Secret already exists, updating..."

aws secretsmanager put-secret-value \
  --secret-id mssql/sa-password \
  --secret-string '{"username":"sa","password":"MyStr0ng!P@ss2024"}' \
  --region $REGION

# Step 2: Associate OIDC provider
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve

# Step 3: Get OIDC ID
OIDC_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text)
OIDC_ID=$(echo $OIDC_URL | sed 's|.*/||')
echo "OIDC ID: $OIDC_ID"

# Step 4: Create IAM policy (skip if exists)
cat > /tmp/mssql-secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ],
    "Resource": "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:mssql/*"
  }]
}
EOF

aws iam create-policy \
  --policy-name mssql-secrets-policy \
  --policy-document file:///tmp/mssql-secrets-policy.json 2>/dev/null || echo "Policy already exists"

# Step 5: Create IAM role with correct trust policy (using explicit role name)
cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:${NAMESPACE}:${SA_NAME}",
        "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF

# Create or update the role
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json 2>/dev/null || \
aws iam update-assume-role-policy \
  --role-name $ROLE_NAME \
  --policy-document file:///tmp/trust-policy.json

# Attach policy to role
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/mssql-secrets-policy

echo ""
echo "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""

# Step 6: Also create a K8s secret as fallback (in case IRSA takes time to propagate)
kubectl create namespace $NAMESPACE 2>/dev/null || true
kubectl create secret generic mssql-sa-password \
  --from-literal=password='MyStr0ng!P@ss2024' \
  -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "AWS setup complete. Deploy with: helm install mssql ./helm/mssql -n mssql --create-namespace"
