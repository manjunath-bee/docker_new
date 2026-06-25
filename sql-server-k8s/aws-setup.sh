#!/bin/bash
# AWS Setup for SQL Server on EKS - Secrets Store CSI Driver + ASCP + IRSA
# Following: https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_ascp_irsa.html
#
# Steps:
#   1. Associate OIDC provider
#   2. Install EBS CSI Driver
#   3. Install Secrets Store CSI Driver + ASCP
#   4. Create secret in AWS Secrets Manager
#   5. Create IAM policy
#   6. Create IRSA service account (handles trust policy automatically)
#   7. Create namespace

CLUSTER_NAME="expense"
REGION="us-east-1"
ACCOUNT_ID="856678556116"
NAMESPACE="mssql"
SA_NAME="mssql-sa"
SECRET_NAME="mssql/sa-password"
POLICY_NAME="mssql-secrets-policy"

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

echo ""
echo "=== Step 3: Install Secrets Store CSI Driver + ASCP ==="
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts 2>/dev/null || true
helm repo update

helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system \
  --set syncSecret.enabled=true

# Install ASCP using kubectl (avoids Helm ServiceAccount conflict)
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

echo "Waiting 20s for pods to start..."
sleep 20
echo "CSI Driver pods:"
kubectl get pods -n kube-system -l app=secrets-store-csi-driver --no-headers
echo "ASCP pods:"
kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws --no-headers

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
echo "Secret ready."

echo ""
echo "=== Step 5: Create IAM policy ==="
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

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
  --policy-name $POLICY_NAME \
  --policy-document file:///tmp/mssql-secrets-policy.json 2>/dev/null || echo "Policy already exists"

echo ""
echo "=== Step 6: Create IRSA Service Account ==="
# This is the KEY step - eksctl handles:
#   - Creating the IAM role with correct trust policy
#   - Annotating the K8s ServiceAccount with the role ARN
#   - Setting up the OIDC condition correctly
eksctl create iamserviceaccount \
  --name $SA_NAME \
  --namespace $NAMESPACE \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --attach-policy-arn $POLICY_ARN \
  --approve \
  --override-existing-serviceaccounts

echo ""
echo "=== Step 7: Verify Service Account ==="
echo "ServiceAccount annotation:"
kubectl get sa $SA_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
echo ""

echo ""
echo "=== Setup complete ==="
echo ""
echo "IMPORTANT: The ServiceAccount was created by eksctl with the correct role ARN."
echo "Your Helm chart's serviceaccount.yaml will conflict with this."
echo "Deploy with:"
echo ""
echo "  helm install mssql ./helm/mssql -n mssql \\"
echo "    --set resources.requests.cpu=500m \\"
echo "    --set resources.limits.cpu=2 \\"
echo "    --set storage.create=false"
echo ""
echo "Verify:"
echo "  kubectl get pods -n mssql -w"
echo "  kubectl logs mssql-mssql-0 -n mssql"
