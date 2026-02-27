#!/bin/bash

# terraform-ec2 — Interactive Deployer
# Prompts for a VPC ID, verifies it exists, and runs terraform plan/apply.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
  echo -e "${BLUE}============================================${NC}"
  echo -e "${BLUE}  terraform-ec2 — Interactive Deployer      ${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo ""
}

print_header

# ─── AWS region ─────────────────────────────────────────────────────────────
read -rp "$(echo -e "${CYAN}AWS region [us-east-1]: ${NC}")" input_region
REGION="${input_region:-us-east-1}"
echo -e "${GREEN}✓ Region: ${REGION}${NC}"
echo ""

# ─── VPC selection ──────────────────────────────────────────────────────────
TF_VPC_ARG=""

while true; do
  read -rp "$(echo -e "${CYAN}Enter a VPC ID to deploy into (press Enter to create a new one): ${NC}")" input_vpc
  echo ""

  if [[ -n "$input_vpc" ]]; then
    # ── VPC ID given — verify it exists in AWS ───────────────────────────────
    echo -e "${YELLOW}Verifying VPC '${input_vpc}' in ${REGION}...${NC}"

    verified_vpc=$(aws ec2 describe-vpcs \
      --region "$REGION" \
      --vpc-ids "$input_vpc" \
      --query 'Vpcs[0].VpcId' \
      --output text 2>/dev/null || echo "")

    if [[ -n "$verified_vpc" && "$verified_vpc" != "None" ]]; then
      echo -e "${GREEN}✓ VPC found: ${verified_vpc}${NC}"
      TF_VPC_ARG="-var=vpc_id=${verified_vpc}"
      break
    else
      echo -e "${RED}✗ VPC '${input_vpc}' was not found in account/region ${REGION}.${NC}"
      echo ""
    fi
  fi

  # ── No VPC ID given, or the provided one wasn't found ────────────────────
  read -rp "$(echo -e "${YELLOW}Create a new VPC (with Internet Gateway and route table) and continue? [y/N]: ${NC}")" create_vpc
  echo ""

  if [[ "${create_vpc,,}" == "y" || "${create_vpc,,}" == "yes" ]]; then
    echo -e "${GREEN}✓ Terraform will create a new VPC.${NC}"
    TF_VPC_ARG=""
    break
  else
    echo -e "${YELLOW}Please enter a valid VPC ID to continue.${NC}"
    echo ""
    # loop back and re-prompt
  fi
done

echo ""

# ─── Terraform ──────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"

echo -e "${YELLOW}[1/3] Initializing Terraform...${NC}"
terraform init -upgrade -input=false
echo -e "${GREEN}✓ Initialized${NC}"
echo ""

echo -e "${YELLOW}[2/3] Planning...${NC}"
if [[ -n "$TF_VPC_ARG" ]]; then
  terraform plan -var="aws_region=${REGION}" "$TF_VPC_ARG"
else
  terraform plan -var="aws_region=${REGION}"
fi
echo ""

read -rp "$(echo -e "${YELLOW}Apply the plan above? [y/N]: ${NC}")" confirm_apply
echo ""

if [[ "${confirm_apply,,}" != "y" && "${confirm_apply,,}" != "yes" ]]; then
  echo -e "${YELLOW}Apply cancelled. No changes were made.${NC}"
  exit 0
fi

echo -e "${YELLOW}[3/3] Applying...${NC}"
if [[ -n "$TF_VPC_ARG" ]]; then
  terraform apply -auto-approve -var="aws_region=${REGION}" "$TF_VPC_ARG"
else
  terraform apply -auto-approve -var="aws_region=${REGION}"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Deployment complete!                      ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

echo -e "${BLUE}Outputs:${NC}"
terraform output
echo ""

INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
if [[ -n "$INSTANCE_ID" ]]; then
  echo -e "${CYAN}Connect via SSM:${NC}"
  echo "  aws ssm start-session --target ${INSTANCE_ID} --region ${REGION}"
  echo ""
  echo -e "${CYAN}Console:${NC}"
  echo "  https://console.aws.amazon.com/ec2/home?region=${REGION}#Instances:instanceId=${INSTANCE_ID}"
  echo ""
fi
