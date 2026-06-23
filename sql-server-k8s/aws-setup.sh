#!/bin/bash
# AWS Setup for SQL Server Secrets Manager Integration
# Run this BEFORE deploying the Kubernetes manifests

CLUSTER_NAME="expense"
REGION="us-east-1"
ACCOUNT_ID="856678556116"
NAMESPACE="mssql"
SA_NAME="mssql-sa"

# Step 1: Create secret in AWS Secrets Manager (with username and password)
aws secretsmanager create-secret \
  --name mssql/sa-password \
  --secret-string '{"username":"sa","password":"YourStr0ng!Passw0rd"}' \
  --region $REGION

# Step 2: Associate OIDC provider (if not already done)
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve

# Step 3: Create IAM policy for Secrets Manager access
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
  --policy-document file:///tmp/mssql-secrets-policy.json

# Step 4: Create IAM service account with IRSA
eksctl create iamserviceaccount \
  --name $SA_NAME \
  --namespace $NAMESPACE \
  --cluster $CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/mssql-secrets-policy \
  --approve \
  --override-existing-serviceaccounts \
  --region $REGION

# Step 5: Install Secrets Store CSI Driver is NOT needed for this approach
# We use an init container with AWS CLI instead

echo "AWS setup complete. Now deploy Kubernetes manifests."
