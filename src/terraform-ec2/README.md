# Terraform Configuration for EC2 Instance

This Terraform configuration launches an EC2 instance into **existing** subnets and security groups in any AWS account. No new VPC, subnet, or security group is created — the configuration validates that the resources you provide actually exist before proceeding.

## Architecture

- **EC2 Instance**: Runs in your existing subnet with your existing security group attached
- **IAM Instance Role & Profile**: Grants the instance an AWS identity for API access and SSM
- **CloudWatch Log Group**: Centralized log destination (`/ec2/<instance_name>`)
- **IMDSv2**: Enforced on the instance metadata service for security

## Prerequisites

1. AWS Account with permissions to create EC2 instances, IAM roles, and CloudWatch log groups
2. Terraform >= 1.0
3. An existing **subnet** (public or private) in your target VPC
4. An existing **security group** in the same VPC
5. *(Optional)* An existing EC2 key pair if you want SSH access

## Setup

1. Copy the example variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your actual values — at minimum you must provide:
   - `subnet_id`: The subnet to launch the instance into
   - `security_group_id`: The security group to attach

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

## Network Configuration

Both `subnet_id` and `security_group_id` are **required** and must already exist in AWS. Terraform will look them up and fail with a clear error if either ID is not found.

The VPC is **automatically derived** from the provided subnet — you do not need to supply a `vpc_id`.

## AMI Selection

| Scenario | Behaviour |
|---|---|
| `ami_id` not set (default) | Latest Amazon Linux 2023 (x86_64, HVM) is resolved automatically |
| `ami_id = "ami-xxx..."` | That exact AMI is used |

## Access Options

### Option A — SSM Session Manager (recommended, no key pair needed)

Leave `key_name` unset and keep `enable_ssm = true` (the default).  After `terraform apply`, connect with:

```bash
aws ssm start-session --target <instance_id> --region <region>
```

The `ssm_session_command` output contains the exact command to run.

### Option B — SSH with a key pair

Set `key_name` to the name of an existing EC2 key pair and ensure port 22 is open in your security group:

```hcl
key_name            = "my-key-pair"
associate_public_ip = true
```

Then connect with:

```bash
ssh -i ~/.ssh/my-key-pair.pem ec2-user@<public_ip>
```

## Variables Reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `subnet_id` | yes | — | Existing subnet ID |
| `security_group_id` | yes | — | Existing security group ID |
| `aws_region` | no | `us-east-1` | AWS region |
| `instance_type` | no | `t3.micro` | EC2 instance type |
| `instance_name` | no | `ec2-instance` | Name tag for the instance |
| `ami_id` | no | `""` (auto) | AMI ID; empty = latest Amazon Linux 2023 |
| `key_name` | no | `""` | EC2 key pair name for SSH |
| `associate_public_ip` | no | `true` | Assign a public IP address |
| `root_volume_size` | no | `20` | Root EBS volume size in GiB |
| `root_volume_type` | no | `gp3` | EBS volume type |
| `user_data` | no | `""` | Cloud-init user data script |
| `enable_ssm` | no | `true` | Attach SSM managed instance policy |
| `tags` | no | `{}` | Extra tags for all resources |

## Outputs

After applying, Terraform will output:

| Output | Description |
|---|---|
| `instance_id` | EC2 instance ID |
| `instance_arn` | EC2 instance ARN |
| `public_ip` | Public IP (empty if `associate_public_ip = false`) |
| `private_ip` | Private IP address |
| `public_dns` | Public DNS hostname |
| `instance_state` | Current instance state |
| `ami_id` | AMI used to launch the instance |
| `vpc_id` | VPC derived from the provided subnet |
| `subnet_id` | Subnet where the instance was launched |
| `security_group_id` | Security group attached to the instance |
| `iam_role_arn` | IAM role ARN |
| `instance_profile_name` | IAM instance profile name |
| `log_group_name` | CloudWatch log group name |
| `console_url` | Direct link to the instance in the AWS Console |
| `ssm_session_command` | AWS CLI command to start an SSM session |

## Cleanup

To terminate the instance and remove all resources created by this configuration:

```bash
terraform destroy
```

> **Note**: The existing subnet and security group you provided are **not** destroyed — only resources created by this Terraform configuration are removed.

## Notes

- The root EBS volume is encrypted by default
- IMDSv2 is enforced (HTTP tokens required) for improved security
- Logs are retained for 14 days (configurable via `retention_in_days` in `ec2.tf`)
- `user_data_replace_on_change = true` means changing user data triggers instance replacement
