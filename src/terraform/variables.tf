variable "cluster_arn" {
  description = "ARN of the ECS cluster where tasks will be scheduled"
  type        = string
}

# ---------------------------------------------------------------------------
# Network configuration
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = <<-EOT
    VPC ID where ECS resources will be deployed.
    Enter a VPC ID (e.g. vpc-0123456789abcdef0), or leave blank ("") to use the
    account's default VPC. A new VPC is created automatically when no default exists.
    Tip: run `terraform output available_vpcs` after init to see existing VPCs.
  EOT
  type    = string

  validation {
    condition     = var.vpc_id == "" || can(regex("^vpc-[a-z0-9]{8,}$", var.vpc_id))
    error_message = "Must be a valid VPC ID (e.g. vpc-1234567890abcdef0) or an empty string."
  }
}

variable "private_subnets" {
  description = <<-EOT
    Subnet IDs for ECS tasks. Enter as an HCL list, e.g. ["subnet-aaa", "subnet-bbb"].
    Recommended: 2+ subnets in different Availability Zones.
    Enter [] to let Terraform auto-discover previously-created subnets or create new ones.
    Tip: run `terraform output available_subnets` after setting vpc_id to see existing subnets.
  EOT
  type    = list(string)
}

variable "ecs_sg_id" {
  description = <<-EOT
    ID of an existing security group to attach to ECS tasks.
    When provided, this security group is used as-is.
    When left empty, Terraform will look for a security group it previously
    created (matched by tag) and create a new one if none is found.
  EOT
  type        = string
  default     = ""
}

variable "subnet_count" {
  description = "Number of private subnets to create when no existing subnets are found."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "container_image" {
  description = "Docker image URI for the ECS task"
  type        = string
}
