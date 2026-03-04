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

### How Terraform prompts for VPC and subnets

`vpc_id` and `private_subnets` have no default values. When they are not set in
`terraform.tfvars`, Terraform will prompt for them interactively at the start of
every `terraform plan` or `terraform apply`:

```
var.private_subnets
  Subnet IDs for ECS tasks. Enter as an HCL list, e.g. ["subnet-aaa", "subnet-bbb"].
  ...
  Enter a value: ["subnet-022e657227078b628", "subnet-044aa97daf963a391"]

var.vpc_id
  VPC ID where ECS resources will be deployed.
  ...
  Enter a value: vpc-0f1e2d3c4b5a6789a
```

To skip the prompts on future runs, add the chosen values to `terraform.tfvars`:

```hcl
vpc_id = "vpc-0f1e2d3c4b5a6789a"

private_subnets = [
  "subnet-022e657227078b628",
  "subnet-044aa97daf963a391",
]
```

> **Tip — not sure which IDs to use?**  Run `terraform init` then `terraform apply`
> once, answer the `vpc_id` prompt with `""` (empty), and after the apply completes
> inspect the discovery outputs:
>
> ```bash
> terraform output available_vpcs     # every VPC in the region
> terraform output available_subnets  # every subnet in the resolved VPC
> ```
>
> Then set the correct IDs in `terraform.tfvars` and re-apply.

### VPC and subnet resolution priority

| Priority | VPC | Subnets |
|----------|-----|---------|
| 1 | `vpc_id` variable (prompted if not set) | `private_subnets` variable (prompted if not set) |
| 2 | Account's default VPC (when `vpc_id = ""`) | Subnets previously created by this config (matched by `ManagedBy=terraform` tag) |
| 3 | Creates a new VPC | Creates new subnets |

### Security group

`ecs_sg_id` is optional (defaults to `""`). Leave it unset and Terraform will
reuse the security group it previously created (matched by tag) or create a new one.

## Setup

1. Copy the example variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your required values:
   - `cluster_arn`: Your ECS cluster ARN
   - `aws_region`: AWS region (default: us-east-1)
   - `container_image`: Your Docker image URI

3. Initialize Terraform:

   ```bash
   terraform init
   ```

4. Review the plan (Terraform will prompt for `vpc_id` and `private_subnets` if not set):

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
