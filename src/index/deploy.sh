#!/bin/bash

# AWS Tag Script - Deployment Helper
# This script automates the build and deployment process

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (loaded from terraform.tfvars)
REGION="eu-west-2"
ACCOUNT_ID="195275642454"
ECR_REPO="tag-script"
IMAGE_TAG="latest"
CLUSTER_ARN="arn:aws:ecs:eu-west-2:195275642454:cluster/default"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AWS Tag Script - Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Build Docker image
echo -e "${YELLOW}[1/6] Building Docker image...${NC}"
docker build -t ${ECR_REPO}:${IMAGE_TAG} .
echo -e "${GREEN}✓ Docker image built successfully${NC}"
echo ""

# Step 2: Login to ECR
echo -e "${YELLOW}[2/6] Logging into Amazon ECR...${NC}"
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
echo -e "${GREEN}✓ Logged into ECR${NC}"
echo ""

# Step 3: Tag image for ECR
echo -e "${YELLOW}[3/6] Tagging Docker image for ECR...${NC}"
docker tag ${ECR_REPO}:${IMAGE_TAG} \
  ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}
echo -e "${GREEN}✓ Image tagged${NC}"
echo ""

# Step 4: Push image to ECR
echo -e "${YELLOW}[4/6] Pushing Docker image to ECR...${NC}"
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}
echo -e "${GREEN}✓ Image pushed to ECR${NC}"
echo ""

# Step 5: Apply Terraform
echo -e "${YELLOW}[5/6] Applying Terraform configuration...${NC}"
cd terraform
terraform init -upgrade
terraform apply -auto-approve
cd ..
echo -e "${GREEN}✓ Terraform applied successfully${NC}"
echo ""

# Step 6: Display deployment info
echo -e "${YELLOW}[6/6] Deployment Summary${NC}"
echo -e "${BLUE}========================================${NC}"
cd terraform
LOG_GROUP=$(terraform output -raw log_group_name 2>/dev/null || echo "/ecs/automation-logs")
SCHEDULE=$(terraform output -raw eventbridge_rule_name 2>/dev/null || echo "automation-schedule")
LOGS_URL=$(terraform output -raw cloudwatch_logs_url 2>/dev/null || echo "N/A")
cd ..

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo ""
echo "Container Image: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"
echo "Log Group: ${LOG_GROUP}"
echo "Schedule: ${SCHEDULE} (every 10 minutes)"
echo ""
echo -e "${BLUE}CloudWatch Logs URL:${NC}"
echo "${LOGS_URL}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Wait up to 10 minutes for the first scheduled run"
echo "2. View logs: aws logs tail ${LOG_GROUP} --follow --region ${REGION}"
echo "3. Or open CloudWatch Logs in AWS Console"
echo ""
echo -e "${BLUE}========================================${NC}"
