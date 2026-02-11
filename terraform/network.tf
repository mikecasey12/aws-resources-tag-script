# Network Infrastructure
# This file creates private subnets and security group for ECS tasks

# Data source to get VPC information
data "aws_vpc" "selected" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

# Data source to get default VPC if no VPC ID is provided
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true

  lifecycle {
    postcondition {
      condition     = self.id != "" && self.id != null
      error_message = "No default VPC found in this region. Please specify a VPC ID using the 'vpc_id' variable."
    }
  }
}

# Data source to get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Validation check to ensure we have a VPC
resource "terraform_data" "vpc_validation" {
  lifecycle {
    precondition {
      condition     = var.vpc_id != "" || length(data.aws_vpc.default) > 0
      error_message = <<-EOT
        No VPC available for resource creation.
        
        Either:
        1. Specify a VPC ID using the 'vpc_id' variable in your terraform.tfvars
        2. Create a default VPC in your AWS account
        
        If you don't have a default VPC, you must explicitly provide a vpc_id.
      EOT
    }
  }
}

# Local values for VPC selection
locals {
  vpc_id = var.vpc_id != "" ? data.aws_vpc.selected[0].id : (
    length(data.aws_vpc.default) > 0 ? data.aws_vpc.default[0].id : null
  )

  # Get CIDR block for the selected VPC
  vpc_cidr = var.vpc_id != "" ? data.aws_vpc.selected[0].cidr_block : (
    length(data.aws_vpc.default) > 0 ? data.aws_vpc.default[0].cidr_block : null
  )

  # Handle backward compatibility with deprecated variables
  # Priority: existing_* variables > deprecated variables > create new
  actual_private_subnets = length(var.existing_private_subnets) > 0 ? var.existing_private_subnets : (
    length(var.private_subnets) > 0 ? var.private_subnets : []
  )
  actual_ecs_sg_id = var.existing_ecs_sg_id != "" ? var.existing_ecs_sg_id : (
    var.ecs_sg_id != "" ? var.ecs_sg_id : ""
  )

  # Use provided subnets if available, otherwise use created ones
  use_existing_subnets = length(local.actual_private_subnets) > 0
  private_subnet_ids   = local.use_existing_subnets ? local.actual_private_subnets : aws_subnet.private[*].id

  # Use provided security group if available, otherwise use created one
  use_existing_sg = local.actual_ecs_sg_id != ""
  ecs_sg_id       = local.use_existing_sg ? local.actual_ecs_sg_id : aws_security_group.ecs_tasks[0].id
}

# Create private subnets
resource "aws_subnet" "private" {
  count = local.use_existing_subnets ? 0 : var.subnet_count

  vpc_id            = local.vpc_id
  cidr_block        = cidrsubnet(local.vpc_cidr, 4, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]

  tags = {
    Name      = "ecs-private-subnet-${count.index + 1}"
    Type      = "private"
    ManagedBy = "terraform"
  }
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  count = local.use_existing_sg ? 0 : 1

  name        = "ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = local.vpc_id

  # Egress rule - allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # Ingress rule - allow traffic within the security group
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow traffic from same security group"
  }

  tags = {
    Name      = "ecs-tasks-sg"
    ManagedBy = "terraform"
  }
}
