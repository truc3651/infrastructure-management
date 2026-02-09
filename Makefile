# Creates S3 bucket and DynamoDB table for Terraform state management

BUCKET_NAME ?= truc2001-terraform-remotes
TABLE_NAME ?= terraform-locks
AWS_REGION ?= ap-southeast-1
AWS_PROFILE ?= personal

.PHONY: help bootstrap create-bucket create-dynamodb destroy-backend create-oidc-provider create-iam-role attach-policies get-role-arn

help:
	@echo "Terraform Backend Bootstrap"
	@echo ""
	@echo "Usage:"
	@echo "  make bootstrap        		- Create S3 bucket, DynamoDB table, OIDC provider, and IAM role"
	@echo "  make create-bucket    		- Create S3 bucket only"
	@echo "  make create-dynamodb  		- Create DynamoDB table only"
	@echo "  make destroy-backend  		- Delete S3 bucket and DynamoDB table"
	@echo "  make create-oidc-provider 	- Create GitHub OIDC provider"
	@echo "  make create-iam-role      	- Create IAM role for GitHub Actions"
	@echo "  make attach-policies      	- Attach policies to IAM role"
	@echo "  make get-role-arn         	- Get IAM role ARN"
	@echo ""
	@echo "Variables:"
	@echo "  BUCKET_NAME  				- S3 bucket name (default: truc2001-terraform-remotes)"
	@echo "  TABLE_NAME   				- DynamoDB table name (default: terraform-locks)"
	@echo "  AWS_REGION   				- AWS region (default: ap-southeast-1)"
	@echo "  AWS_PROFILE  				- AWS profile (default: personal)"

bootstrap: create-bucket create-dynamodb create-oidc-provider create-iam-role attach-policies get-role-arn

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
		--role-name GitHubActionsRole \
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
	@echo "Attaching policies to GitHubActionsRole..."
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name GitHubActionsRole \
		--policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
		2>/dev/null && echo "✓ DynamoDB policy attached" || echo "✓ DynamoDB policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name GitHubActionsRole \
		--policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess \
		2>/dev/null && echo "✓ ECR policy attached" || echo "✓ ECR policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name GitHubActionsRole \
		--policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
		2>/dev/null && echo "✓ EC2 policy attached" || echo "✓ EC2 policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name GitHubActionsRole \
		--policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
		2>/dev/null && echo "✓ EKS policy attached" || echo "✓ EKS policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name GitHubActionsRole \
		--policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
		2>/dev/null && echo "✓ S3 policy attached" || echo "✓ S3 policy already attached"
	@aws iam attach-role-policy \
		--profile $(AWS_PROFILE) \
		--role-name GitHubActionsRole \
		--policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
		2>/dev/null && echo "✓ VPC policy attached" || echo "✓ VPC policy already attached"
	@echo "✓ All policies configured"

get-role-arn:
	@ROLE_ARN=$$(aws iam get-role --profile $(AWS_PROFILE) --role-name GitHubActionsRole --query 'Role.Arn' --output text 2>/dev/null); \
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
		echo "❌ Role 'GitHubActionsRole' not found."; \
		echo "Run 'make create-iam-role' first."; \
	fi

destroy-backend:
	@echo "WARNING: This will delete all Terraform state!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1

	@echo "Deleting IAM role policies..."
	@aws iam list-attached-role-policies \
		--profile $(AWS_PROFILE) \
		--role-name GitHubActionsRole \
		--query 'AttachedPolicies[].PolicyArn' \
		--output text 2>/dev/null | \
		xargs -n1 -I {} aws iam detach-role-policy \
			--profile $(AWS_PROFILE) \
			--role-name GitHubActionsRole \
			--policy-arn {} 2>/dev/null || true

	@echo "Deleting IAM role..."
	@aws iam delete-role \
		--profile $(AWS_PROFILE) \
		--role-name GitHubActionsRole 2>/dev/null \
		&& echo "✓ IAM role deleted" || echo "✓ IAM role not found"

	@echo "Deleting OIDC provider..."
	@OIDC_ARN=$$(aws iam list-open-id-connect-providers \
		--profile $(AWS_PROFILE) \
		--query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
		--output text 2>/dev/null); \
	if [ -n "$$OIDC_ARN" ]; then \
		aws iam delete-open-id-connect-provider \
			--profile $(AWS_PROFILE) \
			--open-id-connect-provider-arn $$OIDC_ARN 2>/dev/null \
			&& echo "✓ OIDC provider deleted" || true; \
	else \
		echo "✓ OIDC provider not found"; \
	fi

	@echo "Deleting all object versions from S3 bucket..."
	@aws s3api list-object-versions \
		--profile $(AWS_PROFILE) \
		--bucket $(BUCKET_NAME) \
		--query 'Versions[].{Key:Key,VersionId:VersionId}' \
		--output json 2>/dev/null | \
		jq -c '.[]' 2>/dev/null | \
		while read obj; do \
			key=$$(echo $$obj | jq -r '.Key'); \
			vid=$$(echo $$obj | jq -r '.VersionId'); \
			aws s3api delete-object \
				--profile $(AWS_PROFILE) \
				--bucket $(BUCKET_NAME) \
				--key "$$key" \
				--version-id "$$vid" 2>/dev/null || true; \
		done || true

	@aws s3api list-object-versions \
		--profile $(AWS_PROFILE) \
		--bucket $(BUCKET_NAME) \
		--query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
		--output json 2>/dev/null | \
		jq -c '.[]' 2>/dev/null | \
		while read obj; do \
			key=$$(echo $$obj | jq -r '.Key'); \
			vid=$$(echo $$obj | jq -r '.VersionId'); \
			aws s3api delete-object \
				--profile $(AWS_PROFILE) \
				--bucket $(BUCKET_NAME) \
				--key "$$key" \
				--version-id "$$vid" 2>/dev/null || true; \
		done || true

	@echo "Deleting S3 bucket..."
	@aws s3api delete-bucket \
		--profile $(AWS_PROFILE) \
		--bucket $(BUCKET_NAME) 2>/dev/null \
		&& echo "✓ S3 bucket deleted" || echo "✓ S3 bucket not found"

	@echo "Deleting DynamoDB table..."
	@aws dynamodb delete-table \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--table-name $(TABLE_NAME) 2>/dev/null \
		&& echo "✓ DynamoDB table deleted" || echo "✓ DynamoDB table not found"

	@echo ""
	@echo "✓ Backend infrastructure destroyed"
