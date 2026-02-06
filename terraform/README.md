# Terraform Configuration for ECS Scheduled Tasks

This Terraform configuration deploys an ECS Fargate task that runs on a schedule using EventBridge (CloudWatch Events).

## Architecture

- **ECS Task Definition**: Defines the containerized application
- **EventBridge Rule**: Scheduled trigger (cron expression)
- **IAM Roles**: Execution and task roles with appropriate permissions
- **CloudWatch Logs**: Centralized logging for task execution

## Prerequisites

1. AWS Account with appropriate permissions
2. Terraform >= 1.0
3. Existing ECS cluster
4. Private subnets with NAT Gateway (for internet access)
5. Security group configured for ECS tasks
6. Docker image pushed to ECR or other registry

## Setup

1. Copy the example variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your actual values:
   - `cluster_arn`: Your ECS cluster ARN
   - `private_subnets`: List of subnet IDs
   - `ecs_sg_id`: Security group ID
   - `aws_region`: AWS region (default: us-east-1)
   - `container_image`: Your Docker image URI

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

- ECS Task Definition
- EventBridge Rule and Target
- CloudWatch Log Group
- IAM Roles and Policies:
  - ECS Execution Role
  - ECS Task Role
  - EventBridge Trigger Role

## Outputs

After applying, Terraform will output:

- Task definition ARN
- EventBridge rule name and ARN
- Log group name
- IAM role ARNs

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Notes

- Tasks run in private subnets without public IP assignment
- Logs are retained for 14 days (configurable in `task_definition.tf`)
- The container must exit after completing its work for proper task lifecycle
