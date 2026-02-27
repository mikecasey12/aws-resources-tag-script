# ---------------------------------------------------------------------------
# Network configuration
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = <<-EOT
    VPC ID to deploy into.
    - Provide a VPC ID (e.g. vpc-0abc1234) to use an existing VPC.
    - Press Enter (leave empty) to use the default VPC, or create a new one
      automatically if no default VPC exists in the region.
  EOT
  type = string

  validation {
    condition     = var.vpc_id == "" || can(regex("^vpc-[a-z0-9]{8,}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g., vpc-0abc1234def567890) or empty."
  }
}

variable "subnet_id" {
  description = <<-EOT
    Existing subnet ID to launch the EC2 instance into.
    When provided, this subnet is used as-is.
    When left empty, Terraform will look for a subnet it previously created (by tag)
    and create a new one if none is found.
  EOT
  type    = string
  default = ""

  validation {
    condition     = var.subnet_id == "" || can(regex("^subnet-[a-z0-9]{8,}$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g., subnet-0abc1234def567890) or empty."
  }
}

variable "security_group_id" {
  description = <<-EOT
    Existing security group ID to attach to the EC2 instance.
    When provided, this security group is used as-is.
    When left empty, Terraform will look for a security group it previously created (by tag)
    and create a new one if none is found.
  EOT
  type    = string
  default = ""

  validation {
    condition     = var.security_group_id == "" || can(regex("^sg-[a-z0-9]{8,}$", var.security_group_id))
    error_message = "security_group_id must be a valid security group ID (e.g., sg-0abc1234def567890) or empty."
  }
}

# ---------------------------------------------------------------------------
# Instance configuration
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "instance_name" {
  description = "Name tag applied to the EC2 instance."
  type        = string
  default     = "ec2-instance"
}

variable "ami_id" {
  description = <<-EOT
    AMI ID to use for the EC2 instance.
    When left empty, the latest Amazon Linux 2023 (x86_64) AMI is used automatically.
  EOT
  type    = string
  default = ""
}

variable "key_name" {
  description = <<-EOT
    Name of an existing EC2 key pair for SSH access.
    Leave empty to launch the instance without a key pair (access via SSM Session Manager only).
  EOT
  type    = string
  default = ""
}

variable "associate_public_ip" {
  description = "Whether to assign a public IP address to the instance."
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GiB."
  type        = number
  default     = 30
}

variable "root_volume_type" {
  description = "EBS volume type for the root device."
  type        = string
  default     = "gp3"
}

variable "user_data" {
  description = <<-EOT
    Shell script content to run on first boot (cloud-init user data).
    Leave empty for no user data.
  EOT
  type    = string
  default = ""
}

variable "enable_ssm" {
  description = <<-EOT
    Attach the AmazonSSMManagedInstanceCore policy to the instance profile,
    allowing SSH-free access via AWS Systems Manager Session Manager.
  EOT
  type    = bool
  default = true
}

# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for resources."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
