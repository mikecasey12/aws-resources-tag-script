# Network Infrastructure
# Resolution priority for subnets and the ECS security group:
#   1. Explicit IDs supplied via variables (private_subnets / ecs_sg_id)
#      — verified to actually exist in AWS; falls through if any ID is missing
#   2. Auto-discovered resources previously created by this configuration (matched by tag)
#   3. Create new resources when neither of the above yields a result

# ---------------------------------------------------------------------------
# VPC resolution
# ---------------------------------------------------------------------------

data "aws_vpc" "selected" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

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

data "aws_availability_zones" "available" {
  state = "available"
}

resource "terraform_data" "vpc_validation" {
  lifecycle {
    precondition {
      condition     = var.vpc_id != "" || length(data.aws_vpc.default) > 0
      error_message = <<-EOT
        No VPC available for resource creation.

        Either:
          1. Specify a VPC ID using the 'vpc_id' variable in your terraform.tfvars
          2. Create a default VPC in your AWS account
      EOT
    }
  }
}

locals {
  vpc_id = var.vpc_id != "" ? data.aws_vpc.selected[0].id : (
    length(data.aws_vpc.default) > 0 ? data.aws_vpc.default[0].id : null
  )

  vpc_cidr = var.vpc_id != "" ? data.aws_vpc.selected[0].cidr_block : (
    length(data.aws_vpc.default) > 0 ? data.aws_vpc.default[0].cidr_block : null
  )
}

# ---------------------------------------------------------------------------
# Step 1 — Verify explicitly provided IDs actually exist in AWS
# data "aws_subnets" / "aws_security_groups" return an EMPTY list (no error)
# when a filter matches nothing, so these are safe "check if exists" queries.
# ---------------------------------------------------------------------------

# Returns only the provided subnet IDs that currently exist in AWS
data "aws_subnets" "provided" {
  count = length(var.private_subnets) > 0 ? 1 : 0

  filter {
    name   = "subnet-id"
    values = var.private_subnets
  }
}

# Returns the provided SG ID only if it currently exists in AWS
data "aws_security_groups" "provided_sg" {
  count = var.ecs_sg_id != "" ? 1 : 0

  filter {
    name   = "group-id"
    values = [var.ecs_sg_id]
  }
}

# ---------------------------------------------------------------------------
# Step 2 — Auto-discover resources previously created by this configuration
# ---------------------------------------------------------------------------

# Subnets tagged by a previous apply of this configuration
data "aws_subnets" "managed" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  tags = {
    ManagedBy = "terraform"
    Type      = "private"
  }
}

# Security group tagged by a previous apply of this configuration
data "aws_security_groups" "managed_ecs" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "group-name"
    values = ["ecs-tasks-sg"]
  }
  tags = {
    ManagedBy = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Resource resolution locals
# Priority: provided IDs (verified) → auto-discovered (by tag) → create new
# ---------------------------------------------------------------------------

locals {
  # Subnets ----------------------------------------------------------------
  # All provided IDs are valid only when AWS confirms every one of them exists
  provided_subnets_valid = (
    length(var.private_subnets) > 0 &&
    length(data.aws_subnets.provided) > 0 &&
    length(data.aws_subnets.provided[0].ids) == length(var.private_subnets)
  )
  discovered_subnet_ids = tolist(data.aws_subnets.managed.ids)
  resolved_subnet_ids = (
    local.provided_subnets_valid ? var.private_subnets : local.discovered_subnet_ids
  )
  use_existing_subnets = length(local.resolved_subnet_ids) > 0
  private_subnet_ids   = local.use_existing_subnets ? local.resolved_subnet_ids : aws_subnet.private[*].id

  # Security group ---------------------------------------------------------
  # The provided SG ID is valid only when AWS confirms it exists
  provided_sg_valid = (
    var.ecs_sg_id != "" &&
    length(data.aws_security_groups.provided_sg) > 0 &&
    length(data.aws_security_groups.provided_sg[0].ids) > 0
  )
  discovered_sg_id = length(data.aws_security_groups.managed_ecs.ids) > 0 ? data.aws_security_groups.managed_ecs.ids[0] : ""
  resolved_sg_id   = local.provided_sg_valid ? var.ecs_sg_id : local.discovered_sg_id
  use_existing_sg  = local.resolved_sg_id != ""
  ecs_sg_id        = local.use_existing_sg ? local.resolved_sg_id : aws_security_group.ecs_tasks[0].id
}

# ---------------------------------------------------------------------------
# Resource creation (skipped when existing resources are found/provided)
# ---------------------------------------------------------------------------

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

resource "aws_security_group" "ecs_tasks" {
  count = local.use_existing_sg ? 0 : 1

  name        = "ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

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
