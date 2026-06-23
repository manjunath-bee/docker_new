# SQL Server 2022 on Kubernetes - Production Deployment (Helm)

## Architecture

- **SQL Server 2022 Enterprise** running as non-root user
- **AWS Secrets Manager** for SA password (via IRSA + init container with AWS CLI)
- **Separate volumes** for data, logs, and backups (performance best practice)
- **Encrypted EBS gp3 volumes** with retain policy
- **NetworkPolicy** restricting access to port 1433 from labeled namespaces only
- **PodDisruptionBudget** preventing accidental eviction
- **Health probes** for automatic restart on failure
- **Resource limits** matching requests to prevent OOM kills
- **Helm chart** for repeatable, configurable deployments

## Files

| File | Purpose |
|------|---------|
| helm/mssql/Chart.yaml | Helm chart metadata |
| helm/mssql/values.yaml | Default configuration values |
| helm/mssql/templates/_helpers.tpl | Template helper functions |
| helm/mssql/templates/namespace.yaml | Dedicated namespace |
| helm/mssql/templates/serviceaccount.yaml | IRSA-enabled service account |
| helm/mssql/templates/configmap.yaml | SQL Server config (TLS, memory, trace flags) |
| helm/mssql/templates/storageclass.yaml | gp3 encrypted EBS storage |
| helm/mssql/templates/networkpolicy.yaml | Firewall rules |
| helm/mssql/templates/service.yaml | Headless + ClusterIP service |
| helm/mssql/templates/statefulset.yaml | StatefulSet with volumeClaimTemplates |
| helm/mssql/templates/pdb.yaml | Pod disruption budget |
| helm/mssql/templates/NOTES.txt | Post-install instructions |
| aws-setup.sh | AWS prerequisites (Secrets Manager, IRSA) |

## Deploy

### Prerequisites (run once)
```bash
# Run the AWS setup script first
chmod +x aws-setup.sh
./aws-setup.sh
```

### Validate (dry run)
```bash
helm install mssql ./helm/mssql -n mssql --create-namespace --dry-run
```

### Install with default values
```bash
helm install mssql ./helm/mssql -n mssql --create-namespace
```

### Install with overrides
```bash
helm install mssql ./helm/mssql -n mssql --create-namespace \
  --set aws.secretName=mysqlrds \
  --set aws.region=us-east-1 \
  --set mssql.pid=Standard \
  --set storage.data.size=100Gi \
  --set service.scheme=internal
```

### Upgrade
```bash
helm upgrade mssql ./helm/mssql -n mssql
```

### Uninstall
```bash
helm uninstall mssql -n mssql
# PVCs are retained (reclaimPolicy: Retain) - delete manually if needed
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| mssql.image | SQL Server image | mcr.microsoft.com/mssql/server |
| mssql.tag | Image tag | 2022-latest |
| mssql.pid | SQL Server edition | Enterprise |
| mssql.memoryLimitMB | Memory limit for SQL | 3072 |
| aws.region | AWS region | us-east-1 |
| aws.secretName | Secrets Manager secret name | mssql/sa-password |
| aws.irsaRoleArn | IAM role ARN for IRSA | (set per environment) |
| storage.className | StorageClass name | mssql-storage |
| storage.data.size | Data volume size | 50Gi |
| storage.log.size | Log volume size | 20Gi |
| storage.backup.size | Backup volume size | 50Gi |
| networkPolicy.enabled | Enable NetworkPolicy | true |
| pdb.enabled | Enable PodDisruptionBudget | true |
| service.scheme | NLB scheme: internal or internet-facing | internal |
| service.subnetIds | Subnet IDs for NLB placement | (auto-detected) |

## Connect

```bash
# Get the NLB DNS name
kubectl get svc mssql-mssql -n mssql

# Connect from outside K8s (DMS, other VPCs, EC2 instances)
sqlcmd -S <nlb-dns-name>,1433 -U sa

# Port forward for local access (alternative)
kubectl port-forward svc/mssql-mssql 1433:1433 -n mssql
sqlcmd -S localhost,1433 -U sa
```

## DMS Endpoint Configuration

Once the NLB is created, use its DNS name as the DMS source endpoint:

```bash
# Get NLB DNS
NLB_DNS=$(kubectl get svc mssql-mssql -n mssql -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Create DMS endpoint
aws dms create-endpoint \
  --endpoint-identifier mssql-source \
  --endpoint-type source \
  --engine-name sqlserver \
  --server-name $NLB_DNS \
  --port 1433 \
  --username sa \
  --password <from-secrets-manager> \
  --database-name <your-db> \
  --region us-east-1
```

If DMS is in another VPC, set up VPC Peering between the DMS VPC and EKS VPC, then update route tables in both VPCs.

## Allow app namespace to connect

Label your app namespace to allow traffic through the NetworkPolicy:

```bash
kubectl label namespace expense access-mssql=true
```

## Security Best Practices Applied

- Non-root container (UID 10001)
- All capabilities dropped
- No privilege escalation
- TLS 1.2 enforced
- NetworkPolicy restricts ingress to labeled namespaces
- SA password stored in AWS Secrets Manager (not in K8s secrets)
- Secrets volume uses tmpfs (memory) - never written to disk
- Service is ClusterIP (not exposed externally)
- Telemetry disabled
- IRSA for AWS authentication (no hardcoded credentials)

## Performance Best Practices Applied

- Separate volumes for data and transaction logs
- gp3 EBS with provisioned IOPS (3000) and throughput (125 MB/s)
- Memory limit set explicitly
- Trace flag 3226 (suppress backup log entries)
- Trace flag 1222 (deadlock detection)
- SQL Agent enabled for maintenance jobs
- CPU requests/limits configured
- Volume expansion enabled for future growth
