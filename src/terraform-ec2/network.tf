# Network Infrastructure
# Resolution priority for subnet and security group:
#   1. Explicit IDs supplied via variables (subnet_id / security_group_id)
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

  tags = merge({ Name = "ec2-vpc", ManagedBy = "terraform" }, var.tags)
}

# Internet gateway and public route table — only needed when we also own the VPC.
# For default/provided VPCs the user is responsible for their own routing.
resource "aws_internet_gateway" "new" {
  count  = local.creating_new_vpc ? 1 : 0
  vpc_id = aws_vpc.new[0].id

  tags = merge({ Name = "ec2-igw", ManagedBy = "terraform" }, var.tags)
}

resource "aws_route_table" "public" {
  count  = local.creating_new_vpc ? 1 : 0
  vpc_id = aws_vpc.new[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.new[0].id
  }

  tags = merge({ Name = "ec2-public-rt", ManagedBy = "terraform" }, var.tags)
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
# Use the plural data sources so a missing ID returns empty rather than hard-erroring.
# ---------------------------------------------------------------------------

data "aws_subnets" "provided" {
  count = var.subnet_id != "" ? 1 : 0

  filter {
    name   = "subnet-id"
    values = [var.subnet_id]
  }
}

data "aws_security_groups" "provided_sg" {
  count = var.security_group_id != "" ? 1 : 0

  filter {
    name   = "group-id"
    values = [var.security_group_id]
  }
}

# ---------------------------------------------------------------------------
# Step 2 — Auto-discover resources previously created by this configuration
#
# count = 0 when creating_new_vpc = true:
#   A brand-new VPC cannot contain pre-existing tagged resources, so the
#   lookup can be skipped unconditionally — and plan_time_vpc_id is never
#   null when these actually run (count = 1).
# ---------------------------------------------------------------------------

data "aws_subnets" "managed" {
  count = local.creating_new_vpc ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [coalesce(local.plan_time_vpc_id, "")]
  }

  tags = {
    ManagedBy = "terraform"
    Type      = "ec2-public"
  }
}

data "aws_security_groups" "managed_sg" {
  count = local.creating_new_vpc ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [coalesce(local.plan_time_vpc_id, "")]
  }
  filter {
    name   = "group-name"
    values = ["ec2-instance-sg"]
  }

  tags = {
    ManagedBy = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Step 3 — Fall back to ANY existing subnet in the VPC
#
# Catches subnets that exist in the VPC but carry no Terraform-managed tags
# (e.g. the default subnets AWS creates automatically in the default VPC).
# Only runs when no subnet was found in steps 1 or 2, and only for
# existing VPCs (a brand-new VPC will have no subnets yet).
# ---------------------------------------------------------------------------

locals {
  # True when steps 1 and 2 both came up empty — computed entirely from
  # variables and data sources so it is always known at plan time.
  need_any_subnet = (
    !local.creating_new_vpc &&
    !(var.subnet_id != "" && length(data.aws_subnets.provided) > 0 && length(data.aws_subnets.provided[0].ids) > 0) &&
    !(length(data.aws_subnets.managed) > 0 && length(data.aws_subnets.managed[0].ids) > 0)
  )
}

data "aws_subnets" "any_in_vpc" {
  count = local.need_any_subnet ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [coalesce(local.plan_time_vpc_id, "")]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ---------------------------------------------------------------------------
# Resource resolution locals
# All values here are deterministic at plan time — no resource attributes used.
# ---------------------------------------------------------------------------

locals {
  # Subnet -----------------------------------------------------------------
  provided_subnet_valid = (
    var.subnet_id != "" &&
    length(data.aws_subnets.provided) > 0 &&
    length(data.aws_subnets.provided[0].ids) > 0
  )
  managed_subnet_ids  = length(data.aws_subnets.managed) > 0 ? tolist(data.aws_subnets.managed[0].ids) : []
  any_subnet_ids      = length(data.aws_subnets.any_in_vpc) > 0 ? tolist(data.aws_subnets.any_in_vpc[0].ids) : []

  resolved_subnet_id = (
    local.provided_subnet_valid ? var.subnet_id : (
      length(local.managed_subnet_ids) > 0 ? local.managed_subnet_ids[0] : (
        length(local.any_subnet_ids) > 0 ? local.any_subnet_ids[0] : ""
      )
    )
  )
  use_existing_subnet = local.resolved_subnet_id != ""
  subnet_id           = local.use_existing_subnet ? local.resolved_subnet_id : aws_subnet.public[0].id

  # Security group ---------------------------------------------------------
  provided_sg_valid = (
    var.security_group_id != "" &&
    length(data.aws_security_groups.provided_sg) > 0 &&
    length(data.aws_security_groups.provided_sg[0].ids) > 0
  )
  discovered_sg_id = (
    length(data.aws_security_groups.managed_sg) > 0 &&
    length(data.aws_security_groups.managed_sg[0].ids) > 0
    ? data.aws_security_groups.managed_sg[0].ids[0]
    : ""
  )
  resolved_sg_id    = local.provided_sg_valid ? var.security_group_id : local.discovered_sg_id
  use_existing_sg   = local.resolved_sg_id != ""
  security_group_id = local.use_existing_sg ? local.resolved_sg_id : aws_security_group.ec2_instance[0].id
}

# ---------------------------------------------------------------------------
# Resource creation (count is fully deterministic at plan time)
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = local.use_existing_subnet ? 0 : 1

  vpc_id                  = local.vpc_id
  cidr_block              = cidrsubnet(local.vpc_cidr, 4, 0)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false # public IP is controlled on the instance resource

  tags = merge(
    { Name = "ec2-public-subnet", Type = "ec2-public", ManagedBy = "terraform" },
    var.tags
  )
}

# Associate the newly-created subnet with the public route table when we own the VPC.
resource "aws_route_table_association" "public" {
  count = local.creating_new_vpc && !local.use_existing_subnet ? 1 : 0

  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "ec2_instance" {
  count = local.use_existing_sg ? 0 : 1

  name        = "ec2-instance-sg"
  description = "Security group for EC2 instance"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH access"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow traffic from same security group"
  }

  tags = merge(
    { Name = "ec2-instance-sg", ManagedBy = "terraform" },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# AMI resolution
# Priority: explicit ami_id variable  →  latest Amazon Linux 2023 (x86_64)
# ---------------------------------------------------------------------------

data "aws_ami" "amazon_linux_2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023[0].id
}
