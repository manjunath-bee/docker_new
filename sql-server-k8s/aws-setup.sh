#!/bin/bash
# AWS Setup for SQL Server on EKS - Secrets Store CSI Driver + ASCP + IRSA
# References:
#   https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_ascp_irsa.html
#   https://secrets-store-csi-driver.sigs.k8s.io/
#
# Prerequisites: EKS cluster, kubectl, helm, eksctl, aws cli

CLUSTER_NAME="expense"
REGION="us-east-1"
ACCOUNT_ID="856678556116"
NAMESPACE="mssql"
SA_NAME="mssql-sa"
SECRET_NAME="mssql/sa-password"
POLICY_NAME="mssql-secrets-policy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

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
echo "=== Step 3: Install Secrets Store CSI Driver ==="
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts 2>/dev/null || true
helm repo update

# tokenRequests is required for IRSA to work with CSI driver
helm upgrade --install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system \
  --set syncSecret.enabled=true \
  --set "tokenRequests[0].audience=sts.amazonaws.com"

echo ""
echo "=== Step 4: Install AWS Secrets Provider (ASCP) ==="
# Use kubectl apply to avoid Helm ServiceAccount ownership conflict
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

echo "Waiting 20s for pods..."
sleep 20
echo "CSI Driver pods:"
kubectl get pods -n kube-system -l app=secrets-store-csi-driver --no-headers
echo "ASCP pods:"
kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws --no-headers

echo ""
echo "=== Step 5: Create/Update secret in AWS Secrets Manager ==="
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
echo "=== Step 6: Create IAM policy ==="
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
echo "=== Step 7: Create namespace ==="
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace already exists"

echo ""
echo "=== Step 8: Create IRSA Service Account ==="
# eksctl handles: IAM role + trust policy + K8s SA annotation
# If eksctl says "excluded", it means the CloudFormation stack exists
# but the K8s SA may not. We handle that below.
eksctl create iamserviceaccount \
  --name $SA_NAME \
  --namespace $NAMESPACE \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --attach-policy-arn $POLICY_ARN \
  --approve \
  --override-existing-serviceaccounts 2>/dev/null || true

# If SA doesn't exist (eksctl excluded it), create manually
if ! kubectl get sa $SA_NAME -n $NAMESPACE &>/dev/null; then
  echo "SA not found, creating manually..."
  ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-${NAMESPACE}-${SA_NAME} \
    --query "Stacks[0].Outputs[?OutputKey=='Role1'].OutputValue" \
    --output text --region $REGION 2>/dev/null)

  if [ -z "$ROLE_ARN" ] || [ "$ROLE_ARN" == "None" ]; then
    echo "ERROR: Could not find IAM role. Delete the eksctl stack and re-run:"
    echo "  aws cloudformation delete-stack --stack-name eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-${NAMESPACE}-${SA_NAME}"
    echo "  Then re-run this script."
    exit 1
  fi

  kubectl create serviceaccount $SA_NAME -n $NAMESPACE
  kubectl annotate serviceaccount $SA_NAME -n $NAMESPACE \
    eks.amazonaws.com/role-arn=$ROLE_ARN
fi

echo ""
echo "=== Step 9: Verify ==="
echo "ServiceAccount:"
kubectl get sa $SA_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations}' && echo ""

echo ""
echo "=== Setup complete ==="
echo ""
echo "Deploy:"
echo "  helm install mssql ./helm/mssql -n mssql \\"
echo "    --set resources.requests.cpu=500m \\"
echo "    --set resources.limits.cpu=2 \\"
echo "    --set storage.create=false"
echo ""
echo "  (use storage.create=true on first deploy if StorageClass doesn't exist)"
echo ""
echo "Verify:"
echo "  kubectl get pods -n mssql -w"
echo "  kubectl describe pod mssql-mssql-0 -n mssql"
echo "  kubectl logs mssql-mssql-0 -n mssql --tail=20"
