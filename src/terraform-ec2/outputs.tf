output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.this.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.this.arn
}

output "public_ip" {
  description = "Public IP address of the EC2 instance (empty when associate_public_ip = false)"
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.this.private_ip
}

output "public_dns" {
  description = "Public DNS hostname of the EC2 instance"
  value       = aws_instance.this.public_dns
}

output "instance_state" {
  description = "Current state of the EC2 instance"
  value       = aws_instance.this.instance_state
}

output "ami_id" {
  description = "AMI ID used to launch the instance"
  value       = aws_instance.this.ami
}

output "vpc_id" {
  description = "VPC ID where the instance is deployed"
  value       = local.vpc_id
}

output "created_vpc" {
  description = "Indicates whether a new VPC was created (true) or an existing one was used (false)"
  value       = local.creating_new_vpc
}

output "subnet_id" {
  description = "Subnet ID where the instance was launched"
  value       = local.subnet_id
}

output "created_subnet" {
  description = "Indicates whether a new subnet was created (true) or an existing one was used (false)"
  value       = !local.use_existing_subnet
}

output "security_group_id" {
  description = "Security group ID attached to the instance"
  value       = local.security_group_id
}

output "created_security_group" {
  description = "Indicates whether a new security group was created (true) or an existing one was used (false)"
  value       = !local.use_existing_sg
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instance profile"
  value       = aws_iam_role.ec2_instance_role.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ec2_logs.name
}

output "console_url" {
  description = "URL to view the instance in the AWS Console"
  value       = "https://console.aws.amazon.com/ec2/home?region=${var.aws_region}#Instances:instanceId=${aws_instance.this.id}"
}

output "ssm_session_command" {
  description = "AWS CLI command to start an SSM Session Manager session (requires enable_ssm = true)"
  value       = "aws ssm start-session --target ${aws_instance.this.id} --region ${var.aws_region}"
}
