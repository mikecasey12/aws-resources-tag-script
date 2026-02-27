# AWS Resource Tagging Automation

Automated solution to discover and tag AWS resources across all regions and services using ECS Fargate scheduled tasks.

## 🎯 Overview

This project automatically:
- Scans all AWS regions for resources
- Identifies resources missing required tags
- Applies standardized tags to resources
- Runs on a schedule (every 10 minutes by default)
- Logs all operations to CloudWatch

### Supported Resources

- **EC2**: Instances, Security Groups
- **IAM**: Roles, Users
- **S3**: Buckets
- **SNS**: Topics
- **All other taggable resources** via Resource Groups Tagging API

## 📋 Prerequisites

### Local Tools
- [Docker Desktop](https://www.docker.com/products/docker-desktop) - For building container images
- [AWS CLI](https://aws.amazon.com/cli/) - For interacting with AWS services
- [Terraform](https://www.terraform.io/downloads) >= 1.0 - For infrastructure deployment

### AWS Resources
- AWS Account with admin or appropriate permissions
- ECS Cluster (Fargate-compatible)
- ECR Repository for Docker images
- Private subnets with NAT Gateway or VPC Endpoints
- Security group allowing outbound HTTPS (port 443)

### AWS Permissions Required
The IAM user/role running deployment needs:
- ECR: Push images
- ECS: Manage task definitions
- IAM: Create and manage roles/policies
- EventBridge: Create and manage rules
- CloudWatch Logs: Create log groups
- Secrets Manager: Read secrets (optional)

## 🚀 Quick Start

### 1. Verify Prerequisites

Run the verification script to check your setup:

```powershell
.\verify-setup.ps1
```

This will check:
- ✅ Docker installed and running
- ✅ AWS CLI configured
- ✅ Terraform installed
- ✅ AWS credentials valid
- ✅ ECR repository exists
- ✅ Network configuration
- ✅ Required files present

### 2. Configure Variables

Edit `terraform/terraform.tfvars` with your AWS details:

```hcl
cluster_arn = "arn:aws:ecs:eu-west-2:195275642454:cluster/default"

private_subnets = [
  "subnet-022e657227078b629",
  "subnet-044aa97daf963a392"
]

ecs_sg_id = "sg-093dad0c7ad0dd85d"
aws_region = "eu-west-2"

container_image = "195275642454.dkr.ecr.eu-west-2.amazonaws.com/tag-script:latest"
```

### 3. Customize Tags (Optional)

Edit the tags in `index.ts` (lines 33-40):

```typescript
const newTags: Record<string, string> = {
  Owner: "Michael@allegion.com",
  ApplicationOwner: "Michael@allegion.com",
  CostAllocation: "International",
  CostRegion: "International",
  Environment: "Production",
  Product: "eTrilock",
};
```

### 4. Deploy

Run the automated deployment script:

```powershell
.\deploy.ps1
```

This will:
1. Build the Docker image
2. Login to ECR
3. Tag and push the image
4. Apply Terraform configuration
5. Display deployment summary with CloudWatch logs URL

### 5. Monitor

View logs in real-time:

```powershell
aws logs tail /ecs/automation-logs --follow --region eu-west-2
```

Or open CloudWatch Logs in AWS Console (URL provided after deployment).

## 📁 Project Structure

```
tag-script/
├── index.ts                    # Main TypeScript script
├── package.json                # Node.js dependencies
├── Dockerfile                  # Container definition
├── docker-compose.yml          # Local testing setup
├── deploy.ps1                  # Windows deployment script
├── deploy.sh                   # Linux/Mac deployment script
├── verify-setup.ps1            # Pre-deployment verification
├── DEPLOYMENT_CHECKLIST.md     # Detailed deployment guide
├── README.md                   # This file
└── terraform/                  # Infrastructure as Code
    ├── provider.tf             # AWS provider configuration
    ├── task_definition.tf      # ECS task definition
    ├── task_scheduler.tf       # EventBridge schedule + IAM
    ├── workers.tf              # IAM roles and permissions
    ├── variables.tf            # Input variables
    ├── outputs.tf              # Output values
    ├── terraform.tfvars        # Your configuration (gitignored)
    └── terraform.tfvars.example # Example configuration
```

## ⚙️ Configuration

### Schedule

Default schedule: **Every 10 minutes**

To modify, edit `terraform/task_scheduler.tf`:

```hcl
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "automation-schedule"
  schedule_expression = "cron(0/10 * * * ? *)" # Every 10 minutes
}
```

**Common schedules:**
- `cron(0 8 * * ? *)` - Daily at 8 AM UTC
- `cron(0 */6 * * ? *)` - Every 6 hours
- `cron(0 8 ? * MON-FRI *)` - Weekdays at 8 AM UTC

### Resource Limits

Current settings (in `terraform/task_definition.tf`):
- CPU: 256 (0.25 vCPU)
- Memory: 512 MB

If you have many resources, increase memory to 1024 MB:

```hcl
cpu    = 256
memory = 1024
```

### Log Retention

Default: 14 days

To change, edit `terraform/task_definition.tf`:

```hcl
resource "aws_cloudwatch_log_group" "automation_logs" {
  name              = "/ecs/automation-logs"
  retention_in_days = 30  # Change to desired days
}
```

## 🔍 How It Works

### Execution Flow

1. **EventBridge** triggers ECS task based on cron schedule
2. **ECS Fargate** starts container in private subnet
3. **Container** runs TypeScript script (`npx tsx index.ts`)
4. **Script** uses IAM role credentials to:
   - Get caller identity (STS)
   - List all AWS regions (EC2)
   - Scan each region for resources:
     - Resource Groups Tagging API (all taggable resources)
     - EC2 instances and security groups
     - IAM roles and users (global)
     - S3 buckets (global)
5. **Script** filters resources missing required tags
6. **Script** applies tags using appropriate AWS SDK for each service
7. **Script** logs progress and summary to CloudWatch
8. **Container** exits, task stops

### Tagging Logic

The script only tags resources that are **missing one or more required tags**:

```typescript
function getResourcesNeedingTags(resources: ResourceWithTags[]): ResourceWithTags[] {
  const requiredTagKeys = Object.keys(newTags);
  
  return resources.filter((resource) => {
    const existingTagKeys = Object.keys(resource.existingTags);
    const missingTags = requiredTagKeys.filter(
      (tagKey) => !existingTagKeys.includes(tagKey)
    );
    return missingTags.length > 0;
  });
}
```

**Existing tags are preserved** - the script merges new tags with existing ones:

```typescript
const mergedTags = { ...resource.existingTags, ...newTags };
```

### Error Handling

- **Retry Logic**: 3 attempts with exponential backoff (1s, 2s, 4s)
- **Rate Limiting**: 100ms delay between resources
- **Graceful Degradation**: Logs errors but continues processing
- **Detailed Logging**: All operations logged to CloudWatch

## 📊 CloudWatch Logs

### Log Structure

```
Using AWS region: eu-west-2
Using IAM role credentials from ECS task role
Starting comprehensive AWS resource tagging process...

Discovering all resources across regions and services...
Found 17 regions: us-east-1, us-east-2, us-west-1, ...

Fetching IAM roles and users (global)...
Found 45 IAM roles and 12 IAM users

Fetching S3 buckets (global)...
Found 23 S3 buckets

Processing region: us-east-1
  Found 156 unique resources in us-east-1
Processing region: us-east-2
  Found 34 unique resources in us-east-2
...

Total resources discovered: 1,234

Resources needing tags: 87 out of 1,234

📊 Resources to tag by type:
  - ec2: 23
  - security-group: 15
  - iam-role: 12
  - s3-bucket: 18
  - sns: 8
  - lambda: 11

[1/87] Tagging ec2: i-0123456789abcdef0
Successfully tagged ec2: arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0
[2/87] Tagging security-group: sg-0123456789abcdef0
Successfully tagged security-group: arn:aws:ec2:us-east-1:123456789012:security-group/sg-0123456789abcdef0
...

============================================================
TAGGING SUMMARY
============================================================
Successfully tagged: 87 resources
Failed to tag: 0 resources
Total execution time: 342.15 seconds

Tagging process completed!
```

### Viewing Logs

**AWS Console:**
1. CloudWatch → Log groups → `/ecs/automation-logs`
2. Click on latest log stream

**AWS CLI:**
```bash
# Follow logs in real-time
aws logs tail /ecs/automation-logs --follow --region eu-west-2

# View last 1 hour
aws logs tail /ecs/automation-logs --since 1h --region eu-west-2

# Search for errors
aws logs tail /ecs/automation-logs --since 1h --filter-pattern "Error" --region eu-west-2
```

## 🔧 Troubleshooting

### Issue: No logs appearing

**Checks:**
1. Verify task is running:
   ```bash
   aws ecs list-tasks --cluster <cluster-arn> --region eu-west-2
   ```
2. Check task status:
   ```bash
   aws ecs describe-tasks --cluster <cluster-arn> --tasks <task-id> --region eu-west-2
   ```
3. Check EventBridge rule:
   ```bash
   aws events describe-rule --name automation-schedule --region eu-west-2
   ```

### Issue: Task fails to start

**Common causes:**
- Docker image not in ECR → Run `.\deploy.ps1` again
- Network connectivity → Check NAT Gateway or VPC endpoints
- IAM permissions → Review execution role in AWS Console
- Invalid configuration → Run `terraform plan` to check

### Issue: Script errors

**Check logs for specific errors:**
```bash
aws logs tail /ecs/automation-logs --since 1h --filter-pattern "Error" --region eu-west-2
```

**Common errors:**
- `AccessDenied` → Check task role IAM permissions
- `NetworkingError` → Check NAT Gateway and security group
- `ResourceNotFoundException` → Check AWS service availability in region

### Issue: Resources not being tagged

**Possible reasons:**
1. Resources already have all required tags (script only tags missing tags)
2. IAM permissions insufficient for specific resource type
3. Resource type not supported by the script

**Debug:**
```bash
# View full logs to see which resources were scanned
aws logs tail /ecs/automation-logs --since 1h --region eu-west-2
```

## 🔒 Security Considerations

### IAM Roles

The solution uses **ECS IAM roles** (not static credentials):
- ✅ **Execution Role**: For ECS infrastructure (pulling images, writing logs)
- ✅ **Task Role**: For AWS API calls (tagging resources)
- ✅ No static AWS credentials in environment variables
- ✅ Credentials automatically rotated by AWS

### Network Security

- ✅ Tasks run in **private subnets** (no public IP)
- ✅ Internet access via **NAT Gateway** or **VPC Endpoints**
- ✅ Security group restricts traffic

### Secrets Management

- ✅ No credentials committed to Git (.env in .gitignore)
- ✅ Sensitive values in AWS Secrets Manager (optional)
- ✅ Terraform state should be in S3 with encryption

### Least Privilege

The task role has only necessary permissions:
- ✅ Read/write tags
- ✅ List and describe resources
- ✅ No delete or modify permissions

## 📚 Additional Documentation

- **[DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md)** - Comprehensive deployment guide with verification steps
- **[terraform/README.md](./terraform/README.md)** - Terraform-specific documentation

## 🤝 Contributing

To modify the script:

1. Edit `index.ts` with your changes
2. Test locally (optional):
   ```bash
   npm install
   npx tsx index.ts
   ```
3. Rebuild and redeploy:
   ```powershell
   .\deploy.ps1
   ```

## 📝 License

Internal use only - Allegion

## 👤 Author

Michael @ Allegion
Product: eTrilock

## 🔄 Version History

- **v1.0** (2024-02-06)
  - Initial release
  - Support for EC2, IAM, S3, SNS, Security Groups
  - ECS Fargate deployment
  - CloudWatch logging
  - Automated deployment scripts
