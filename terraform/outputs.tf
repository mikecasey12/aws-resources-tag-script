output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.automation_task.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.schedule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.schedule.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.automation_logs.name
}

output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_exec_role.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "cloudwatch_logs_url" {
  description = "URL to view CloudWatch logs in AWS Console"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.automation_logs.name, "/", "$252F")}"
}

output "vpc_id" {
  description = "VPC ID where resources are deployed"
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used for ECS tasks"
  value       = local.private_subnet_ids
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = local.ecs_sg_id
}

output "created_subnets" {
  description = "Indicates whether new subnets were created (true) or existing ones were used (false)"
  value       = !local.use_existing_subnets
}

output "created_security_group" {
  description = "Indicates whether a new security group was created (true) or an existing one was used (false)"
  value       = !local.use_existing_sg
}
