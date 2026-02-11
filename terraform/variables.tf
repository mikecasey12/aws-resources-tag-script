variable "cluster_arn" {
  description = "ARN of the ECS cluster where tasks will be scheduled"
  type        = string
}

# Network Configuration Variables
variable "vpc_id" {
  description = "VPC ID where resources will be created. If not provided, uses the default VPC (if available)"
  type        = string
  default     = ""

  validation {
    condition     = var.vpc_id == "" || can(regex("^vpc-[a-z0-9]{8,}$", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID (e.g., vpc-1234567890abcdef0) or empty to use the default VPC."
  }
}

variable "existing_private_subnets" {
  description = "List of existing private subnet IDs for ECS tasks. If not provided, new subnets will be created"
  type        = list(string)
  default     = []
}

variable "existing_ecs_sg_id" {
  description = "Existing security group ID for ECS tasks. If not provided, a new security group will be created"
  type        = string
  default     = ""
}

variable "subnet_count" {
  description = "Number of private subnets to create (only used if existing_private_subnets is not provided)"
  type        = number
  default     = 2
}

# Deprecated variables - use existing_private_subnets and existing_ecs_sg_id instead
variable "private_subnets" {
  description = "(Deprecated) Use existing_private_subnets instead. List of private subnet IDs for ECS tasks"
  type        = list(string)
  default     = []
}

variable "ecs_sg_id" {
  description = "(Deprecated) Use existing_ecs_sg_id instead. Security group ID for ECS tasks"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "container_image" {
  description = "Docker image URI for the ECS task"
  type        = string
}
