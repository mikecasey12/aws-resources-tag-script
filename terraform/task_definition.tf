resource "aws_ecs_task_definition" "automation_task" {
  family                   = "automation-runner"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "worker"
    image     = var.container_image
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "NODE_ENV", value = "production" }
    ]
    # secrets = [
    #   { 
    #     name      = "AWS_ACCESS_KEY_ID", 
    #     valueFrom = "${data.aws_secretsmanager_secret.aws_keys.arn}:AWS_ACCESS_KEY_ID::" 
    #   },
    #   { 
    #     name      = "AWS_SECRET_ACCESS_KEY", 
    #     valueFrom = "${data.aws_secretsmanager_secret.aws_keys.arn}:AWS_SECRET_ACCESS_KEY::" 
    #   },
    # ]
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.automation_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_cloudwatch_log_group" "automation_logs" {
  name              = "/ecs/automation-logs"
  retention_in_days = 14
}

