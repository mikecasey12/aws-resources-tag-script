# Terraform Configuration for ECS Scheduled Tasks

This Terraform configuration deploys an ECS Fargate task that runs on a schedule using EventBridge (CloudWatch Events).

## Architecture

- **ECS Task Definition**: Defines the containerized application
- **EventBridge Rule**: Scheduled trigger (cron expression)
- **IAM Roles**: Execution and task roles with appropriate permissions
- **CloudWatch Logs**: Centralized logging for task execution
- **Network Resources**: Private subnets and security group (can be created or use existing)

## Prerequisites

1. AWS Account with appropriate permissions
2. Terraform >= 1.0
3. Existing ECS cluster
4. Docker image pushed to ECR or other registry
5. **(Optional)** Existing VPC with private subnets and security group, or let Terraform create them

## Network Configuration

This configuration supports two network setup options:

### Option 1: Create New Network Resources (Recommended)

Terraform will automatically create private subnets and a security group for your ECS tasks. This is the simplest approach for new deployments.

In `terraform.tfvars`:
```hcl
# Optional: Specify VPC ID (if not provided, uses default VPC if available)
# IMPORTANT: If your account has no default VPC, you MUST specify a vpc_id
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"

# Optional: Number of subnets to create (default: 2)
subnet_count = 2
```

**Important**: If you don't have a default VPC in your AWS account/region, you must explicitly provide a `vpc_id`. The configuration will fail with a clear error message if no VPC is available.

### Option 2: Use Existing Network Resources

If you already have private subnets and a security group, you can reference them:

In `terraform.tfvars`:
```hcl
existing_private_subnets = [
  "subnet-xxxxxxxxxxxxxxxxx",
  "subnet-xxxxxxxxxxxxxxxxx"
]
existing_ecs_sg_id = "sg-xxxxxxxxxxxxxxxxx"
```

**Note**: The security group must allow:
- Outbound HTTPS (port 443) for AWS API calls
- Subnets should have internet access via NAT Gateway or VPC endpoints

## Setup

1. Copy the example variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your actual values:
   - `cluster_arn`: Your ECS cluster ARN
   - `aws_region`: AWS region (default: us-east-1)
   - `container_image`: Your Docker image URI
   - Network configuration (see options above)

3. Initialize Terraform:

   ```bash
   terraform init
   ```

4. Review the plan:

   ```bash
   terraform plan
   ```

5. Apply the configuration:
   ```bash
   terraform apply
   ```

## Schedule Configuration

The default schedule is set to run daily at 8 AM UTC:

```hcl
schedule_expression = "cron(0 8 * * ? *)"
```

To modify the schedule, edit the `schedule_expression` in `task_scheduler.tf`.

### Cron Expression Format

```
cron(Minutes Hours Day-of-month Month Day-of-week Year)
```

Examples:

- `cron(0 8 * * ? *)` - Every day at 8:00 AM UTC
- `cron(0 */6 * * ? *)` - Every 6 hours
- `cron(0 8 ? * MON-FRI *)` - Every weekday at 8:00 AM UTC

## Resources Created

### Always Created:
- ECS Task Definition
- EventBridge Rule and Target
- CloudWatch Log Group
- IAM Roles and Policies:
  - ECS Execution Role
  - ECS Task Role
  - EventBridge Trigger Role

### Conditionally Created (if not using existing resources):
- Private Subnets (default: 2 subnets across different AZs)
- Security Group for ECS tasks

## Outputs

After applying, Terraform will output:

- Task definition ARN
- EventBridge rule name and ARN
- Log group name
- IAM role ARNs
- VPC ID
- Private subnet IDs (created or existing)
- Security group ID (created or existing)
- Indicators showing if resources were created or reused

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Notes

- Tasks run in private subnets with public IP assignment enabled (for internet access without NAT Gateway)
- If creating new subnets, they will be created across multiple availability zones for high availability
- Created security groups allow all outbound traffic and intra-security-group communication
- Logs are retained for 14 days (configurable in `task_definition.tf`)
- The container must exit after completing its work for proper task lifecycle
- Backward compatibility is maintained - old variable names (`private_subnets`, `ecs_sg_id`) still work
