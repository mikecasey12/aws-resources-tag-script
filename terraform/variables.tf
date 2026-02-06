variable "cluster_arn" {
  description = "ARN of the ECS cluster where tasks will be scheduled"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "ecs_sg_id" {
  description = "Security group ID for ECS tasks"
  type        = string
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
