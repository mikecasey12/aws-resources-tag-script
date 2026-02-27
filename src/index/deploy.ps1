# AWS Tag Script - Deployment Helper (PowerShell)
# This script automates the build and deployment process for Windows

$ErrorActionPreference = "Stop"

# Configuration (loaded from terraform.tfvars)
$REGION = "eu-west-2"
$ACCOUNT_ID = "195275642454"
$ECR_REPO = "tag-script"
$IMAGE_TAG = "latest"
$CLUSTER_ARN = "arn:aws:ecs:eu-west-2:195275642454:cluster/default"

Write-Host "========================================" -ForegroundColor Blue
Write-Host "AWS Tag Script - Deployment" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# Step 1: Build Docker image
Write-Host "[1/6] Building Docker image..." -ForegroundColor Yellow
docker build -t "${ECR_REPO}:${IMAGE_TAG}" .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "✓ Docker image built successfully" -ForegroundColor Green
Write-Host ""

# Step 2: Login to ECR
Write-Host "[2/6] Logging into Amazon ECR..." -ForegroundColor Yellow
$ecrPassword = aws ecr get-login-password --region $REGION
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$ecrPassword | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "✓ Logged into ECR" -ForegroundColor Green
Write-Host ""

# Step 3: Tag image for ECR
Write-Host "[3/6] Tagging Docker image for ECR..." -ForegroundColor Yellow
docker tag "${ECR_REPO}:${IMAGE_TAG}" "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "✓ Image tagged" -ForegroundColor Green
Write-Host ""

# Step 4: Push image to ECR
Write-Host "[4/6] Pushing Docker image to ECR..." -ForegroundColor Yellow
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "✓ Image pushed to ECR" -ForegroundColor Green
Write-Host ""

# Step 5: Apply Terraform
Write-Host "[5/6] Applying Terraform configuration..." -ForegroundColor Yellow
Push-Location terraform
terraform init -upgrade
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
terraform apply -auto-approve
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location
Write-Host "✓ Terraform applied successfully" -ForegroundColor Green
Write-Host ""

# Step 6: Display deployment info
Write-Host "[6/6] Deployment Summary" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Blue
Push-Location terraform
try {
    $LOG_GROUP = terraform output -raw log_group_name 2>$null
    if (!$LOG_GROUP) { $LOG_GROUP = "/ecs/automation-logs" }
    
    $SCHEDULE = terraform output -raw eventbridge_rule_name 2>$null
    if (!$SCHEDULE) { $SCHEDULE = "automation-schedule" }
    
    $LOGS_URL = terraform output -raw cloudwatch_logs_url 2>$null
    if (!$LOGS_URL) { $LOGS_URL = "N/A" }
} finally {
    Pop-Location
}

Write-Host "Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Container Image: $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"
Write-Host "Log Group: $LOG_GROUP"
Write-Host "Schedule: $SCHEDULE (every 10 minutes)"
Write-Host ""
Write-Host "CloudWatch Logs URL:" -ForegroundColor Blue
Write-Host "$LOGS_URL"
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Wait up to 10 minutes for the first scheduled run"
Write-Host "2. View logs: aws logs tail $LOG_GROUP --follow --region $REGION"
Write-Host "3. Or open CloudWatch Logs in AWS Console"
Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
