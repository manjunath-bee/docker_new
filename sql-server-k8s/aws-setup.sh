#!/bin/bash
# AWS Setup for SQL Server on EKS
# Installs all prerequisites needed before running: helm install mssql ./helm/mssql -n mssql

CLUSTER_NAME="expense"
REGION="us-east-1"
ACCOUNT_ID="856678556116"
NAMESPACE="mssql"
SA_NAME="mssql-sa"
ROLE_NAME="mssql-secrets-role"
SECRET_NAME="mssql/sa-password"

set -e

echo "=== Step 1: Associate OIDC provider ==="
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve

echo ""
echo "=== Step 2: Install EBS CSI Driver ==="
eksctl create addon --name aws-ebs-csi-driver \
  --cluster $CLUSTER_NAME --region $REGION 2>/dev/null || echo "EBS CSI driver already installed"
echo "Verifying EBS CSI driver..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver --no-headers | head -3

echo ""
echo "=== Step 3: Install Secrets Store CSI Driver ==="
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm repo update
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system --set syncSecret.enabled=true
helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws \
  -n kube-system

echo "Waiting 30s for CSI pods..."
sleep 30
kubectl get pods -n kube-system -l app=secrets-store-csi-driver --no-headers
kubectl get pods -n kube-system -l app=secrets-store-csi-driver-provider-aws --no-headers

echo ""
echo "=== Step 4: Create/Update secret in AWS Secrets Manager ==="
aws secretsmanager create-secret \
  --name $SECRET_NAME \
  --secret-string '{"username":"sa","password":"MyStr0ng!P@ss2024"}' \
  --region $REGION 2>/dev/null || \
aws secretsmanager put-secret-value \
  --secret-id $SECRET_NAME \
  --secret-string '{"username":"sa","password":"MyStr0ng!P@ss2024"}' \
  --region $REGION
echo "Secret created/updated."

echo ""
echo "=== Step 5: Get OIDC ID ==="
OIDC_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text)
OIDC_ID=$(echo $OIDC_URL | sed 's|.*/||')
echo "OIDC ID: $OIDC_ID"

echo ""
echo "=== Step 6: Create IAM policy ==="
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/mssql-secrets-policy"

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

echo ""
echo "=== Step 7: Create IRSA role ==="
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

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json 2>/dev/null || \
aws iam update-assume-role-policy \
  --role-name $ROLE_NAME \
  --policy-document file:///tmp/trust-policy.json

aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN

echo ""
echo "=== Step 8: Verify IRSA role ==="
aws iam get-role --role-name $ROLE_NAME --query "Role.Arn" --output text || {
  echo "ERROR: Failed to create IAM role $ROLE_NAME."
  exit 1
}

echo ""
echo "=== Step 9: Create namespace ==="
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace already exists"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Deploy:"
echo "  helm install mssql ./helm/mssql -n mssql"
echo ""
echo "Verify:"
echo "  kubectl get pods -n mssql -w"
echo "  kubectl logs mssql-mssql-0 -n mssql -c mssql"
