#Requires -Version 5.1
# terraform-ec2 — Interactive Deployer (PowerShell)
# Prompts for a VPC ID, verifies it exists, and runs terraform plan/apply.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Write-Header {
    Write-Host "============================================" -ForegroundColor Blue
    Write-Host "  terraform-ec2 — Interactive Deployer      " -ForegroundColor Blue
    Write-Host "============================================" -ForegroundColor Blue
    Write-Host ""
}

function Prompt-Input {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan -NoNewline
    return (Read-Host)
}

function Confirm-YesNo {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow -NoNewline
    $answer = (Read-Host).Trim().ToLower()
    return ($answer -eq 'y' -or $answer -eq 'yes')
}

# ─── Header ──────────────────────────────────────────────────────────────────

Write-Header

# ─── AWS region ──────────────────────────────────────────────────────────────

$inputRegion = Prompt-Input "AWS region [us-east-1]: "
$Region = if ($inputRegion.Trim() -ne '') { $inputRegion.Trim() } else { 'us-east-1' }
Write-Host "[OK] Region: $Region" -ForegroundColor Green
Write-Host ""

# ─── VPC selection ───────────────────────────────────────────────────────────

$TfVpcArg = $null

while ($true) {
    $inputVpc = (Prompt-Input "Enter a VPC ID to deploy into (press Enter to create a new one): ").Trim()
    Write-Host ""

    if ($inputVpc -ne '') {
        # ── VPC ID given — verify it exists in AWS ───────────────────────────
        Write-Host "Verifying VPC '$inputVpc' in $Region..." -ForegroundColor Yellow

        $verifiedVpc = aws ec2 describe-vpcs --region $Region --vpc-ids $inputVpc --query "Vpcs[0].VpcId" --output text 2>$null

        if ($LASTEXITCODE -eq 0 -and $verifiedVpc -and $verifiedVpc -ne 'None') {
            Write-Host "[OK] VPC found: $verifiedVpc" -ForegroundColor Green
            $TfVpcArg = "-var=vpc_id=$verifiedVpc"
            break
        }
        else {
            Write-Host "[ERROR] VPC '$inputVpc' was not found in account/region $Region." -ForegroundColor Red
            Write-Host ""
        }
    }

    # ── No VPC ID given, or the provided one wasn't found ────────────────────
    $createVpc = Confirm-YesNo "Create a new VPC (with Internet Gateway and route table) and continue? [y/N]: "
    if ($createVpc) {
        Write-Host ""
        Write-Host "[OK] Terraform will create a new VPC." -ForegroundColor Green
        $TfVpcArg = $null
        break
    }
    else {
        Write-Host ""
        Write-Host "Please enter a valid VPC ID to continue." -ForegroundColor Yellow
        Write-Host ""
        # loop back and re-prompt
    }
}

Write-Host ""

# ─── Terraform ───────────────────────────────────────────────────────────────

Set-Location $ScriptDir

Write-Host "[1/3] Initializing Terraform..." -ForegroundColor Yellow
terraform init -upgrade -input=false
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "[OK] Initialized" -ForegroundColor Green
Write-Host ""

Write-Host "[2/3] Planning..." -ForegroundColor Yellow
if ($TfVpcArg) {
    terraform plan -var="aws_region=$Region" $TfVpcArg
}
else {
    terraform plan -var="aws_region=$Region"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""

$confirmApply = Confirm-YesNo "Apply the plan above? [y/N]: "
if (-not $confirmApply) {
    Write-Host ""
    Write-Host "Apply cancelled. No changes were made." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "[3/3] Applying..." -ForegroundColor Yellow
if ($TfVpcArg) {
    terraform apply -auto-approve -var="aws_region=$Region" $TfVpcArg
}
else {
    terraform apply -auto-approve -var="aws_region=$Region"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Deployment complete!                      " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

Write-Host "Outputs:" -ForegroundColor Blue
terraform output
Write-Host ""

$instanceId = terraform output -raw instance_id 2>$null
if ($LASTEXITCODE -eq 0 -and $instanceId) {
    Write-Host "Connect via SSM:" -ForegroundColor Cyan
    Write-Host "  aws ssm start-session --target $instanceId --region $Region"
    Write-Host ""
    Write-Host "Console:" -ForegroundColor Cyan
    Write-Host "  https://console.aws.amazon.com/ec2/home?region=$Region#Instances:instanceId=$instanceId"
    Write-Host ""
}
