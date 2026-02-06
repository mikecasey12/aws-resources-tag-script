# The Infrastructure Role (Execution)
resource "aws_iam_role" "ecs_exec_role" {
  name = "universal-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_standard" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Explicit CloudWatch Logs permissions for ECS execution role
resource "aws_iam_role_policy" "ecs_exec_logs" {
  name = "ecs-cloudwatch-logs-policy"
  role = aws_iam_role.ecs_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ]
        Resource = "${aws_cloudwatch_log_group.automation_logs.arn}:*"
      }
    ]
  })
}

# The Logic Role (Task)
resource "aws_iam_role" "ecs_task_role" {
  name = "universal-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
}

# Fetch AWS keys
data "aws_secretsmanager_secret" "aws_keys" {
  name = "ECSDeploySecrets"
}

# Trust document used by both
data "aws_iam_policy_document" "ecs_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}