# Network Infrastructure
# Resolution priority for subnets and the ECS security group:
#   1. Explicit IDs supplied via variables (private_subnets / ecs_sg_id)
#      — verified to actually exist in AWS; falls through if any ID is missing
#   2. Auto-discovered resources previously created by this configuration (matched by tag)
#   3. Create new resources when neither of the above yields a result

# ---------------------------------------------------------------------------
# VPC resolution
# Priority: explicit vpc_id  →  default VPC  →  create new VPC
# ---------------------------------------------------------------------------

data "aws_vpc" "selected" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

# aws_vpcs (plural) returns an empty list when no default VPC exists — safe to
# use as a conditional unlike the singular data source which hard-errors.
data "aws_vpcs" "default" {
  count = var.vpc_id == "" ? 1 : 0

  filter {
    name   = "isDefault"
    values = ["true"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  has_default_vpc = (
    var.vpc_id == "" &&
    length(data.aws_vpcs.default) > 0 &&
    length(data.aws_vpcs.default[0].ids) > 0
  )
  default_vpc_id = local.has_default_vpc ? data.aws_vpcs.default[0].ids[0] : null

  # True when a brand-new VPC will be created — known at plan time because it
  # depends only on variables and data sources, never on resource attributes.
  creating_new_vpc = var.vpc_id == "" && !local.has_default_vpc

  # VPC ID that is ALWAYS known at plan time.
  # When creating_new_vpc = true this is null; data sources that need a VPC ID
  # for their filter use coalesce(..., "") and are guarded with count = 0 so
  # they are never executed. This breaks the "count depends on unknown value"
  # chain that would otherwise flow through aws_vpc.new[0].id.
  plan_time_vpc_id = var.vpc_id != "" ? data.aws_vpc.selected[0].id : (
    local.has_default_vpc ? local.default_vpc_id : null
  )
}

# Full details of the default VPC (only fetched when it actually exists)
data "aws_vpc" "default" {
  count = local.has_default_vpc ? 1 : 0
  id    = local.default_vpc_id
}

# Created only when no vpc_id is supplied and no default VPC exists
resource "aws_vpc" "new" {
  count = local.creating_new_vpc ? 1 : 0

  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name      = "ecs-vpc"
    ManagedBy = "terraform"
  }
}

locals {
  # vpc_id may reference aws_vpc.new[0].id (known after apply) — used only in
  # resource bodies, never in count/for_each arguments.
  vpc_id = var.vpc_id != "" ? data.aws_vpc.selected[0].id : (
    local.has_default_vpc ? local.default_vpc_id : aws_vpc.new[0].id
  )

  vpc_cidr = var.vpc_id != "" ? data.aws_vpc.selected[0].cidr_block : (
    local.has_default_vpc ? data.aws_vpc.default[0].cidr_block : aws_vpc.new[0].cidr_block
  )
}

# ---------------------------------------------------------------------------
# Step 1 — Verify explicitly provided IDs actually exist in AWS
# These data sources filter by ID, not by VPC, so they never touch vpc_id.
# ---------------------------------------------------------------------------

data "aws_subnets" "provided" {
  count = length(var.private_subnets) > 0 ? 1 : 0

  filter {
    name   = "subnet-id"
    values = var.private_subnets
  }
}

data "aws_security_groups" "provided_sg" {
  count = var.ecs_sg_id != "" ? 1 : 0

  filter {
    name   = "group-id"
    values = [var.ecs_sg_id]
  }
}

# ---------------------------------------------------------------------------
# Step 2 — Auto-discover resources previously created by this configuration
#
# count = 0 when creating_new_vpc = true:
#   • A brand-new VPC cannot contain pre-existing tagged resources, so the
#     lookup can be skipped unconditionally.
#   • This also ensures the filter value (plan_time_vpc_id) is never null
#     when the data source actually runs (count = 1).
# ---------------------------------------------------------------------------

data "aws_subnets" "managed" {
  count = local.creating_new_vpc ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [coalesce(local.plan_time_vpc_id, "")]
  }
  tags = {
    ManagedBy = "terraform"
    Type      = "private"
  }
}

data "aws_security_groups" "managed_ecs" {
  count = local.creating_new_vpc ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [coalesce(local.plan_time_vpc_id, "")]
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
# All values here are deterministic at plan time — no resource attributes used.
# ---------------------------------------------------------------------------

locals {
  # Subnets ----------------------------------------------------------------
  provided_subnets_valid = (
    length(var.private_subnets) > 0 &&
    length(data.aws_subnets.provided) > 0 &&
    length(data.aws_subnets.provided[0].ids) == length(var.private_subnets)
  )
  discovered_subnet_ids = length(data.aws_subnets.managed) > 0 ? tolist(data.aws_subnets.managed[0].ids) : []
  resolved_subnet_ids   = local.provided_subnets_valid ? var.private_subnets : local.discovered_subnet_ids
  use_existing_subnets  = length(local.resolved_subnet_ids) > 0
  private_subnet_ids    = local.use_existing_subnets ? local.resolved_subnet_ids : aws_subnet.private[*].id

  # Security group ---------------------------------------------------------
  provided_sg_valid = (
    var.ecs_sg_id != "" &&
    length(data.aws_security_groups.provided_sg) > 0 &&
    length(data.aws_security_groups.provided_sg[0].ids) > 0
  )
  discovered_sg_id = (
    length(data.aws_security_groups.managed_ecs) > 0 &&
    length(data.aws_security_groups.managed_ecs[0].ids) > 0
    ? data.aws_security_groups.managed_ecs[0].ids[0]
    : ""
  )
  resolved_sg_id  = local.provided_sg_valid ? var.ecs_sg_id : local.discovered_sg_id
  use_existing_sg = local.resolved_sg_id != ""
  ecs_sg_id       = local.use_existing_sg ? local.resolved_sg_id : aws_security_group.ecs_tasks[0].id
}

# ---------------------------------------------------------------------------
# Resource creation (count is fully deterministic at plan time)
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
