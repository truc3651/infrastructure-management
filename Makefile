# Creates S3 bucket and DynamoDB table for Terraform state management

DOCKER_USERNAME ?= trucstre
DOCKER_PASSWORD ?= $(shell echo "$$DOCKER_PASSWORD")
BUCKET_NAME ?= truc2001-terraform-remotes
TABLE_NAME ?= terraform-locks
AWS_REGION ?= ap-southeast-1
AWS_PROFILE ?= personal
ROLE_NAME ?= GitHubActionsRole

NEO4J_SECRET_NAME ?= neo4j/prod/backend-users
NEO4J_URI ?= neo4j+s://2915d8e5.databases.neo4j.io
NEO4J_USERNAME ?= 2915d8e5
NEO4J_PASSWORD ?= tKDn9RrKI9zrS9KKePg5r2VExvIzsm1dg8PRxheuvsE

.PHONY: help bootstrap create-bucket create-dynamodb destroy-backend create-oidc-provider create-iam-role attach-policies attach-custom-policies get-role-arn clean-policies delete-docker-secret create-neo4j-secret

help:
	@echo "Terraform Backend Bootstrap"
	@echo ""
	@echo "Usage:"
	@echo "  make bootstrap        		- Create S3 bucket, Create ECR Docker secret, DynamoDB table, OIDC provider, and IAM role"
	@echo "  make create-docker-secret  - Create ECR Docker secret"
	@echo "  make create-neo4j-secret   - Create Neo4j credentials secret"
	@echo "  make create-bucket    		- Create S3 bucket only"
	@echo "  make create-dynamodb  		- Create DynamoDB table only"
	@echo "  make destroy-backend  		- Delete S3 bucket and DynamoDB table"
	@echo "  make create-oidc-provider 	- Create GitHub OIDC provider"
	@echo "  make create-iam-role      	- Create IAM role for GitHub Actions"
	@echo "  make attach-policies      	- Attach AWS managed policies to IAM role"
	@echo "  make attach-custom-policies  	- Create and attach custom policies to IAM role"
	@echo "  make clean-policies       	- Remove and recreate all custom policies"
	@echo "  make get-role-arn         	- Get IAM role ARN"
	@echo ""
	@echo "Variables:"
	@echo "  BUCKET_NAME  				- S3 bucket name (default: truc2001-terraform-remotes)"
	@echo "  TABLE_NAME   				- DynamoDB table name (default: terraform-locks)"
	@echo "  AWS_REGION   				- AWS region (default: ap-southeast-1)"
	@echo "  AWS_PROFILE  				- AWS profile (default: personal)"
	@echo "  ROLE_NAME    				- IAM role name (default: GitHubActionsRole)"

bootstrap: create-docker-secret create-bucket create-dynamodb create-oidc-provider create-iam-role attach-policies attach-custom-policies get-role-arn create-neo4j-secret

create-docker-secret:
	@echo "Creating ECR Docker secret..."
	@aws secretsmanager create-secret \
		--profile $(AWS_PROFILE) \
		--name "ecr-pullthroughcache/dockerhub" \
		--description "Docker Hub credentials for ECR pull through cache" \
		--secret-string '{"username":"$(DOCKER_USERNAME)","password":"$(DOCKER_PASSWORD)"}' \
		2>/dev/null && echo "✓ Docker secret created" || echo "✓ Docker secret already exists"

create-bucket:
	@echo "Creating S3 bucket: $(BUCKET_NAME)"
	@aws s3api create-bucket \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--bucket $(BUCKET_NAME) \
		--create-bucket-configuration LocationConstraint=$(AWS_REGION) \
		2>/dev/null && echo "✓ S3 bucket created" || echo "✓ S3 bucket already exists"

	@echo "Enabling versioning..."
	@aws s3api put-bucket-versioning \
		--profile $(AWS_PROFILE) \
		--bucket $(BUCKET_NAME) \
		--versioning-configuration Status=Enabled \
		2>/dev/null && echo "✓ Versioning enabled" || echo "✓ Versioning already enabled"

	@echo "Enabling server-side encryption..."
	@aws s3api put-bucket-encryption \
		--profile $(AWS_PROFILE) \
		--bucket $(BUCKET_NAME) \
		--server-side-encryption-configuration '{ \
			"Rules": [{ \
				"ApplyServerSideEncryptionByDefault": { \
					"SSEAlgorithm": "AES256" \
				}, \
				"BucketKeyEnabled": true \
			}] \
		}' 2>/dev/null && echo "✓ Encryption enabled" || echo "✓ Encryption already enabled"

	@echo "Blocking public access..."
	@aws s3api put-public-access-block \
		--profile $(AWS_PROFILE) \
		--bucket $(BUCKET_NAME) \
		--public-access-block-configuration \
			BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
		2>/dev/null && echo "✓ Public access blocked" || echo "✓ Public access already blocked"

	@echo "Applying bucket policy..."
	@aws s3api put-bucket-policy \
		--profile $(AWS_PROFILE) \
		--bucket $(BUCKET_NAME) \
		--policy '{ \
			"Version": "2012-10-17", \
			"Statement": [ \
				{ \
					"Sid": "EnforceTLS", \
					"Effect": "Deny", \
					"Principal": "*", \
					"Action": "s3:*", \
					"Resource": [ \
						"arn:aws:s3:::$(BUCKET_NAME)", \
						"arn:aws:s3:::$(BUCKET_NAME)/*" \
					], \
					"Condition": { \
						"Bool": { \
							"aws:SecureTransport": "false" \
						} \
					} \
				}, \
				{ \
					"Sid": "DenyIncorrectEncryptionHeader", \
					"Effect": "Deny", \
					"Principal": "*", \
					"Action": "s3:PutObject", \
					"Resource": "arn:aws:s3:::$(BUCKET_NAME)/*", \
					"Condition": { \
						"StringNotEquals": { \
							"s3:x-amz-server-side-encryption": "AES256" \
						} \
					} \
				} \
			] \
		}' 2>/dev/null && echo "✓ Bucket policy applied" || echo "✓ Bucket policy already applied"

	@echo "✓ S3 bucket configuration complete"

create-dynamodb:
	@echo "Creating DynamoDB table: $(TABLE_NAME)"
	@aws dynamodb create-table \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--table-name $(TABLE_NAME) \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST \
		2>/dev/null && echo "✓ DynamoDB table created" || echo "✓ DynamoDB table already exists"

	@echo "Waiting for table to be active..."
	@aws dynamodb wait table-exists \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--table-name $(TABLE_NAME) \
		2>/dev/null || true

	@echo "✓ DynamoDB table ready"

create-oidc-provider:
	@echo "Creating GitHub OIDC provider..."
	@ACCOUNT_ID=$$(aws sts get-caller-identity --profile $(AWS_PROFILE) --query Account --output text); \
	aws iam create-open-id-connect-provider \
		--profile $(AWS_PROFILE) \
		--url https://token.actions.githubusercontent.com \
		--client-id-list sts.amazonaws.com \
		--thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
		2>/dev/null && echo "✓ OIDC provider created" || echo "✓ OIDC provider already exists"

create-iam-role:
	@echo "Creating IAM role for GitHub Actions..."
	@ACCOUNT_ID=$$(aws sts get-caller-identity --profile $(AWS_PROFILE) --query Account --output text); \
	aws iam create-role \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--assume-role-policy-document '{ \
			"Version": "2012-10-17", \
			"Statement": [ \
				{ \
					"Effect": "Allow", \
					"Principal": { \
						"Federated": "arn:aws:iam::'"$$ACCOUNT_ID"':oidc-provider/token.actions.githubusercontent.com" \
					}, \
					"Action": "sts:AssumeRoleWithWebIdentity", \
					"Condition": { \
						"StringEquals": { \
							"token.actions.githubusercontent.com:aud": "sts.amazonaws.com" \
						}, \
						"StringLike": { \
							"token.actions.githubusercontent.com:sub": "repo:truc3651/infrastructure-management:*" \
						} \
					} \
				} \
			] \
		}' 2>/dev/null && echo "✓ IAM role created" || echo "✓ IAM role already exists";

attach-policies:
	@echo "Attaching AWS managed policies..."
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
		2>/dev/null && echo "✓ DynamoDB policy attached" || echo "✓ DynamoDB policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess \
		2>/dev/null && echo "✓ ECR policy attached" || echo "✓ ECR policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
		2>/dev/null && echo "✓ EC2 policy attached" || echo "✓ EC2 policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
		2>/dev/null && echo "✓ EKS Cluster policy attached" || echo "✓ EKS Cluster policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
		2>/dev/null && echo "✓ S3 policy attached" || echo "✓ S3 policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
		2>/dev/null && echo "✓ VPC policy attached" || echo "✓ VPC policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
		2>/dev/null && echo "✓ IAM Full Access policy attached" || echo "✓ IAM Full Access policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
		2>/dev/null && echo "✓ CloudWatch Logs Full Access policy attached" || echo "✓ CloudWatch Logs Full Access policy already attached"
	@echo "✓ AWS managed policies attached"

attach-custom-policies:
	@echo "Creating consolidated custom IAM policy..."
	
	@echo "Creating GitHubActions Consolidated FullAccess policy..."
	@aws iam create-policy \
		--profile $(AWS_PROFILE) \
		--policy-name GitHubActions-Consolidated-FullAccess \
		--policy-document '{ \
			"Version": "2012-10-17", \
			"Statement": [ \
				{ \
					"Sid": "CloudWatchLogsFullAccess", \
					"Effect": "Allow", \
					"Action": "logs:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "IAMFullAccess", \
					"Effect": "Allow", \
					"Action": "iam:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "STSFullAccess", \
					"Effect": "Allow", \
					"Action": "sts:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "KMSFullAccess", \
					"Effect": "Allow", \
					"Action": "kms:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "EKSFullAccess", \
					"Effect": "Allow", \
					"Action": "eks:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "AutoScalingFullAccess", \
					"Effect": "Allow", \
					"Action": "autoscaling:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "ELBFullAccess", \
					"Effect": "Allow", \
					"Action": "elasticloadbalancing:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "RDSFullAccess", \
					"Effect": "Allow", \
					"Action": "rds:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "SecretsManagerFullAccess", \
					"Effect": "Allow", \
					"Action": "secretsmanager:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "AmazonMSKFullAccess", \
					"Effect": "Allow", \
					"Action": "kafka:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "MSKConnectFullAccess", \
					"Effect": "Allow", \
					"Action": "kafkaconnect:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "S3FullAccess", \
					"Effect": "Allow", \
					"Action": "s3:*", \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "MSKConnectRequiredPermissions", \
					"Effect": "Allow", \
					"Action": [ \
						"iam:PassRole", \
						"ec2:CreateNetworkInterface", \
						"ec2:DeleteNetworkInterface", \
						"ec2:DescribeNetworkInterfaces", \
						"ec2:DescribeSubnets", \
						"ec2:DescribeSecurityGroups", \
						"ec2:DescribeVpcs", \
						"kafka-cluster:*" \
					], \
					"Resource": "*" \
				}, \
				{ \
					"Sid": "AllowPassMSKConnectRole", \
					"Effect": "Allow", \
					"Action": "iam:PassRole", \
					"Resource": "arn:aws:iam::909561835411:role/msk-connect-*", \
					"Condition": { \
						"StringEquals": { \
							"iam:PassedToService": "kafkaconnect.amazonaws.com" \
						} \
					} \
				} \
			] \
		}' 2>/dev/null && echo "✓ Consolidated policy created" || echo "✓ Consolidated policy already exists"

	@ACCOUNT_ID=$$(aws sts get-caller-identity --profile $(AWS_PROFILE) --query Account --output text); \
	aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::$$ACCOUNT_ID:policy/GitHubActions-Consolidated-FullAccess \
		2>/dev/null && echo "✓ Consolidated policy attached" || echo "✓ Consolidated policy already attached"
	
	@echo "✓ All custom policies attached"

clean-policies:
	@echo "Cleaning old individual custom policies and creating consolidated policy..."
	@ACCOUNT_ID=$$(aws sts get-caller-identity --profile $(AWS_PROFILE) --query Account --output text); \
	for policy in GitHubActions-IAM-FullAccess GitHubActions-CloudWatchLogs-FullAccess GitHubActions-KMS-FullAccess GitHubActions-EKS-FullAccess GitHubActions-AutoScaling-FullAccess GitHubActions-ELB-FullAccess GitHubActions-STS-FullAccess; do \
		echo "Detaching $$policy..."; \
		aws iam detach-role-policy \
			--profile $(AWS_PROFILE) \
			--role-name $(ROLE_NAME) \
			--policy-arn arn:aws:iam::$$ACCOUNT_ID:policy/$$policy 2>/dev/null || true; \
		echo "Deleting $$policy..."; \
		aws iam delete-policy \
			--profile $(AWS_PROFILE) \
			--policy-arn arn:aws:iam::$$ACCOUNT_ID:policy/$$policy 2>/dev/null || true; \
	done
	@echo "Detaching old consolidated policy if exists..."
	@ACCOUNT_ID=$$(aws sts get-caller-identity --profile $(AWS_PROFILE) --query Account --output text); \
	aws iam detach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name $(ROLE_NAME) \
		--policy-arn arn:aws:iam::$$ACCOUNT_ID:policy/GitHubActions-Consolidated-FullAccess 2>/dev/null || true
	@echo "Deleting old consolidated policy if exists..."
	@aws iam delete-policy \
		--profile $(AWS_PROFILE) \
		--policy-arn arn:aws:iam::$$ACCOUNT_ID:policy/GitHubActions-Consolidated-FullAccess 2>/dev/null || true
	@echo "✓ Old policies cleaned"
	@echo "Recreating consolidated policy..."
	@$(MAKE) attach-custom-policies

create-neo4j-secret:
	@echo "Creating Neo4j credentials secret..."
	@aws secretsmanager create-secret \
		--profile $(AWS_PROFILE) \
		--name "$(NEO4J_SECRET_NAME)" \
		--description "Neo4j graph database credentials" \
		--secret-string '{"uri":"$(NEO4J_URI)","username":"$(NEO4J_USERNAME)","password":"$(NEO4J_PASSWORD)"}' \
		2>/dev/null && echo "✓ Neo4j secret created" || echo "✓ Neo4j secret already exists"

get-role-arn:
	@ROLE_ARN=$$(aws iam get-role --profile $(AWS_PROFILE) --role-name $(ROLE_NAME) --query 'Role.Arn' --output text 2>/dev/null); \
	if [ -n "$$ROLE_ARN" ]; then \
		echo ""; \
		echo "========================================"; \
		echo "Role ARN: $$ROLE_ARN"; \
		echo ""; \
		echo "📋 Add to GitHub:"; \
		echo "   Settings → Secrets and variables → Actions → New repository variable"; \
		echo "   Name: AWS_ROLE_ARN"; \
		echo "   Value: $$ROLE_ARN"; \
		echo "========================================"; \
		echo ""; \
	else \
		echo "❌ Role '$(ROLE_NAME)' not found."; \
		echo "Run 'make create-iam-role' first."; \
	fi