# ---------------------------------------------------------------------------
# IAM — instance profile
# Grants the instance an identity so it can call AWS APIs and (optionally)
# be reached via SSM Session Manager without an SSH key.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_instance_role" {
  name               = "${var.instance_name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  tags = merge(
    { Name = "${var.instance_name}-instance-role", ManagedBy = "terraform" },
    var.tags
  )
}

# Allow the instance to write logs to CloudWatch
resource "aws_iam_role_policy" "ec2_cloudwatch_logs" {
  name = "${var.instance_name}-cloudwatch-logs-policy"
  role = aws_iam_role.ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.ec2_logs.arn}:*"
      }
    ]
  })
}

# SSM Session Manager — attach only when enable_ssm = true
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  count      = var.enable_ssm ? 1 : 0
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.instance_name}-instance-profile"
  role = aws_iam_role.ec2_instance_role.name

  tags = merge(
    { Name = "${var.instance_name}-instance-profile", ManagedBy = "terraform" },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ec2_logs" {
  name              = "/ec2/${var.instance_name}"
  retention_in_days = 14

  tags = merge(
    { Name = "/ec2/${var.instance_name}", ManagedBy = "terraform" },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [local.security_group_id]
  associate_public_ip_address = var.associate_public_ip
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  key_name                    = var.key_name != "" ? var.key_name : null
  user_data                   = var.user_data != "" ? var.user_data : null
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  tags = merge(
    { Name = var.instance_name, ManagedBy = "terraform" },
    var.tags
  )

  volume_tags = merge(
    { Name = "${var.instance_name}-root", ManagedBy = "terraform" },
    var.tags
  )
}
