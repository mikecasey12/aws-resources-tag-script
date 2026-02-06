# AWS Tag Script - Pre-Deployment Verification Script
# Checks all prerequisites before deployment

$ErrorActionPreference = "Continue"

$REGION = "eu-west-2"
$ACCOUNT_ID = "195275642454"
$ECR_REPO = "tag-script"
$SUBNETS = @("subnet-022e657227078b629", "subnet-044aa97daf963a392")
$SECURITY_GROUP = "sg-093dad0c7ad0dd85d"
$CLUSTER_ARN = "arn:aws:ecs:eu-west-2:195275642454:cluster/default"

$allChecksPassed = $true

function Test-Command {
    param($Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Write-Check {
    param($Message, $Status, $Details = "")
    if ($Status) {
        Write-Host "[✓] $Message" -ForegroundColor Green
        if ($Details) { Write-Host "    $Details" -ForegroundColor Gray }
    } else {
        Write-Host "[✗] $Message" -ForegroundColor Red
        if ($Details) { Write-Host "    $Details" -ForegroundColor Yellow }
        $script:allChecksPassed = $false
    }
}

Write-Host "========================================" -ForegroundColor Blue
Write-Host "Pre-Deployment Verification" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# 1. Check Docker
Write-Host "Checking Local Environment..." -ForegroundColor Cyan
Write-Host ""

$dockerInstalled = Test-Command "docker"
Write-Check "Docker installed" $dockerInstalled "Required to build container image"

if ($dockerInstalled) {
    try {
        $dockerVersion = docker --version
        docker ps | Out-Null 2>&1
        Write-Check "Docker daemon running" ($LASTEXITCODE -eq 0) $dockerVersion
    } catch {
        Write-Check "Docker daemon running" $false "Start Docker Desktop"
    }
}

# 2. Check AWS CLI
$awsInstalled = Test-Command "aws"
Write-Check "AWS CLI installed" $awsInstalled "Required to interact with AWS"

if ($awsInstalled) {
    $awsVersion = aws --version 2>&1
    Write-Host "    $awsVersion" -ForegroundColor Gray
}

# 3. Check Terraform
$terraformInstalled = Test-Command "terraform"
Write-Check "Terraform installed" $terraformInstalled "Required to deploy infrastructure"

if ($terraformInstalled) {
    $terraformVersion = terraform version | Select-Object -First 1
    Write-Host "    $terraformVersion" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Checking AWS Configuration..." -ForegroundColor Cyan
Write-Host ""

if ($awsInstalled) {
    # 4. Check AWS credentials
    try {
        $identity = aws sts get-caller-identity --region $REGION 2>&1 | ConvertFrom-Json
        Write-Check "AWS credentials configured" $true "Account: $($identity.Account)"
        
        $correctAccount = $identity.Account -eq $ACCOUNT_ID
        Write-Check "Correct AWS account" $correctAccount "Expected: $ACCOUNT_ID, Got: $($identity.Account)"
        
    } catch {
        Write-Check "AWS credentials configured" $false "Run 'aws configure' to set up credentials"
    }
    
    # 5. Check ECR repository
    try {
        $repo = aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION 2>&1 | ConvertFrom-Json
        Write-Check "ECR repository exists" $true "$($repo.repositories[0].repositoryUri)"
    } catch {
        Write-Check "ECR repository exists" $false "Create ECR repo: aws ecr create-repository --repository-name $ECR_REPO --region $REGION"
    }
    
    # 6. Check ECS cluster
    try {
        $cluster = aws ecs describe-clusters --clusters $CLUSTER_ARN --region $REGION 2>&1 | ConvertFrom-Json
        $clusterActive = $cluster.clusters[0].status -eq "ACTIVE"
        Write-Check "ECS cluster exists" $clusterActive "Status: $($cluster.clusters[0].status)"
    } catch {
        Write-Check "ECS cluster exists" $false "Cluster not found: $CLUSTER_ARN"
    }
    
    Write-Host ""
    Write-Host "Checking Network Configuration..." -ForegroundColor Cyan
    Write-Host ""
    
    # 7. Check subnets
    try {
        $subnetList = ($SUBNETS -join " ")
        $subnets = aws ec2 describe-subnets --subnet-ids $SUBNETS --region $REGION 2>&1 | ConvertFrom-Json
        Write-Check "Private subnets exist" ($subnets.Subnets.Count -eq $SUBNETS.Count) "Found $($subnets.Subnets.Count) subnets"
        
        # Check for NAT Gateway
        foreach ($subnet in $subnets.Subnets) {
            $routeTable = aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$($subnet.SubnetId)" --region $REGION 2>&1 | ConvertFrom-Json
            $hasNatRoute = $false
            foreach ($rt in $routeTable.RouteTables) {
                foreach ($route in $rt.Routes) {
                    if ($route.NatGatewayId) {
                        $hasNatRoute = $true
                        break
                    }
                }
            }
            
            if ($hasNatRoute) {
                Write-Host "    Subnet $($subnet.SubnetId): NAT Gateway route found" -ForegroundColor Gray
            } else {
                Write-Host "    Subnet $($subnet.SubnetId): No NAT Gateway route" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Check "Private subnets exist" $false "Unable to verify subnets"
    }
    
    # 8. Check security group
    try {
        $sg = aws ec2 describe-security-groups --group-ids $SECURITY_GROUP --region $REGION 2>&1 | ConvertFrom-Json
        Write-Check "Security group exists" $true "$($sg.SecurityGroups[0].GroupName)"
        
        # Check for outbound HTTPS rule
        $hasHttpsEgress = $false
        foreach ($rule in $sg.SecurityGroups[0].IpPermissionsEgress) {
            if (($rule.IpProtocol -eq "-1") -or 
                (($rule.FromPort -eq 443) -and ($rule.ToPort -eq 443))) {
                $hasHttpsEgress = $true
                break
            }
        }
        Write-Check "Security group allows outbound HTTPS" $hasHttpsEgress "Required for AWS API calls"
    } catch {
        Write-Check "Security group exists" $false "Security group not found: $SECURITY_GROUP"
    }
    
    # 9. Check Secrets Manager (optional)
    try {
        $secret = aws secretsmanager describe-secret --secret-id "ECSDeploySecrets" --region $REGION 2>&1 | ConvertFrom-Json
        Write-Check "Secrets Manager secret exists" $true "ECSDeploySecrets (optional, currently not used)"
    } catch {
        Write-Host "[i] Secrets Manager secret not found (optional, not currently used)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Checking Project Files..." -ForegroundColor Cyan
Write-Host ""

# 10. Check required files
$requiredFiles = @(
    "index.ts",
    "package.json",
    "Dockerfile",
    "terraform/provider.tf",
    "terraform/task_definition.tf",
    "terraform/task_scheduler.tf",
    "terraform/workers.tf",
    "terraform/variables.tf",
    "terraform/outputs.tf",
    "terraform/terraform.tfvars"
)

foreach ($file in $requiredFiles) {
    $exists = Test-Path $file
    Write-Check "$file" $exists
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue

if ($allChecksPassed) {
    Write-Host "All checks passed! ✓" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now run the deployment:" -ForegroundColor Cyan
    Write-Host "  .\deploy.ps1" -ForegroundColor White
} else {
    Write-Host "Some checks failed! ✗" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the issues above before deploying." -ForegroundColor Yellow
    Write-Host "See DEPLOYMENT_CHECKLIST.md for detailed instructions." -ForegroundColor Yellow
}

Write-Host "========================================" -ForegroundColor Blue
