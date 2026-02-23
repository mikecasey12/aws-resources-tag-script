variable "cluster_arn" {
  description = "ARN of the ECS cluster where tasks will be scheduled"
  type        = string
}

# ---------------------------------------------------------------------------
# Network configuration
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID where resources will be created. Leave empty to use the default VPC."
  type        = string
  default     = ""

  validation {
    condition     = var.vpc_id == "" || can(regex("^vpc-[a-z0-9]{8,}$", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID (e.g., vpc-1234567890abcdef0) or empty to use the default VPC."
  }
}

variable "private_subnets" {
  description = <<-EOT
    List of existing private subnet IDs to use for ECS tasks.
    When provided, these subnets are used as-is.
    When left empty, Terraform will look for subnets it previously created (by tag)
    and create new ones if none are found.
  EOT
  type        = list(string)
  default     = []
}

variable "ecs_sg_id" {
  description = <<-EOT
    Existing security group ID for ECS tasks.
    When provided, this security group is used as-is.
    When left empty, Terraform will look for a security group it previously created
    (by tag) and create a new one if none is found.
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
