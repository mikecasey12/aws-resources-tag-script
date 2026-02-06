# The Trigger Role
resource "aws_iam_role" "eb_trigger_role" {
  name               = "eventbridge-ecs-trigger-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "events.amazonaws.com" }
      },
      {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ecs-tasks.amazonaws.com"
          }
      }
    ]
  })
}

# Permission for EventBridge to run tasks
resource "aws_iam_role_policy" "eb_run_task" {
  role = aws_iam_role.eb_trigger_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = ["${aws_ecs_task_definition.automation_task.arn_without_revision}:*"]
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [aws_iam_role.ecs_exec_role.arn, aws_iam_role.ecs_task_role.arn]
      },
      {
        Action   = ["secretsmanager:GetSecretValue"]
        Effect   = "Allow"
        Resource = [data.aws_secretsmanager_secret.aws_keys.arn]
      }
    ]
  })
}

# Comprehensive Permissions for AWS Resource Tagging Script
resource "aws_iam_role_policy" "tagging_permissions" {
  name = "tagging-permissions"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          # Resource Groups Tagging API
          "tag:GetResources",
          "tag:TagResources",
          "tag:GetTagKeys",
          "tag:GetTagValues",
          
          # IAM permissions
          "iam:GetRole",
          "iam:GetUser",
          "iam:ListRoles",
          "iam:ListUsers",
          "iam:ListRoleTags",
          "iam:ListUserTags",
          "iam:TagRole",
          "iam:TagUser",
          
          # EC2 permissions
          "ec2:DescribeRegions",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateTags",
          
          # S3 permissions
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          
          # SNS permissions
          "sns:ListTopics",
          "sns:ListTagsForResource",
          "sns:TagResource",
          
          # STS for account identity
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# The Schedule (Cron)
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "automation-schedule"
  schedule_expression = "cron(0/10 * * * ? *)" # Every 5 minutes
}

# Connecting Schedule to Task
resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  arn       = var.cluster_arn
  role_arn  = aws_iam_role.eb_trigger_role.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.automation_task.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = var.private_subnets
      security_groups  = [var.ecs_sg_id]
      assign_public_ip = true  # Changed to true for internet access without NAT Gateway
    }
  }
}