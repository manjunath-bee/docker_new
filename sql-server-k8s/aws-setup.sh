#!/bin/bash
# AWS Setup for SQL Server on EKS using Secrets Store CSI Driver + ASCP
# This uses the recommended AWS approach: CSI driver mounts secrets as files
# References:
#   https://secrets-store-csi-driver.sigs.k8s.io/
#   https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_ascp_irsa.html

CLUSTER_NAME="expense"
REGION="us-east-1"
ACCOUNT_ID="856678556116"
NAMESPACE="mssql"
SA_NAME="mssql-sa"
ROLE_NAME="mssql-secrets-role"
SECRET_NAME="mssql/sa-password"

set -e

echo "=== Step 1: Create/Update secret in AWS Secrets Manager ==="
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
echo "=== Step 2: Associate OIDC provider ==="
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve

echo ""
echo "=== Step 3: Get OIDC ID ==="
OIDC_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text)
OIDC_ID=$(echo $OIDC_URL | sed 's|.*/||')
echo "OIDC ID: $OIDC_ID"

echo ""
echo "=== Step 4: Install Secrets Store CSI Driver ==="
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system \
  --set syncSecret.enabled=true

echo ""
echo "=== Step 5: Install AWS Secrets Provider (ASCP) ==="
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws \
  -n kube-system

echo ""
echo "=== Step 6: Verify CSI driver and ASCP are running ==="
echo "Waiting 30s for pods to start..."
sleep 30
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl get pods -n kube-system -l app=secrets-store-csi-driver-provider-aws

echo ""
echo "=== Step 7: Create IAM policy for Secrets Manager access ==="
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
echo "=== Step 8: Create IAM role with IRSA trust policy ==="
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
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/mssql-secrets-policy

echo ""
echo "=== Step 9: Create namespace ==="
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace already exists"

echo ""
echo "=== Setup complete ==="
echo "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "Next steps:"
echo "  1. Deploy: helm install mssql ./helm/mssql -n mssql"
echo "  2. Verify: kubectl get pods -n mssql"
echo "  3. Logs:   kubectl logs mssql-mssql-0 -n mssql -c mssql"
