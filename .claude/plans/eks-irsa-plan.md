# EKS IRSA (IAM Roles for Service Accounts) Plan

## Overview

Set up IAM Roles for Service Accounts (IRSA) to allow EKS pods to access AWS services (Secrets Manager, SES) with least-privilege permissions.

---

## Current Infrastructure Analysis

| Service | Network (Security Group) | IAM Permissions | Status |
|---------|-------------------------|-----------------|--------|
| **PostgreSQL (RDS)** | ✅ Configured | N/A (uses credentials) | Ready |
| **Secrets Manager** | ✅ Outbound allowed | ❌ Missing | Needs IRSA |
| **SES** | ✅ Outbound allowed | ❌ Missing | Needs IRSA |
| **ElastiCache** | ❌ Not configured | N/A (uses credentials) | Needs SG rule |
| **MemoryDB** | ❌ Not configured | N/A (uses credentials) | Needs SG rule |

### What's Already Working

**PostgreSQL (RDS)**:
- Security group allows EKS nodes → RDS on port 5432 (`modules/rds-cluster/main.tf:27-33`)
- App fetches credentials from Secrets Manager, then connects via host/port

**EKS OIDC Provider**:
- Already configured in `modules/eks-cluster/main.tf`
- Outputs: `oidc_provider_arn`, `oidc_provider`

---

## Why IRSA?

**Without IRSA**: All pods on a node share the node's IAM role. If one pod needs Secrets Manager access, ALL pods get it.

**With IRSA**: Each Kubernetes ServiceAccount gets its own IAM role. Pods only get permissions their ServiceAccount has.

```
┌─────────────────────────────────────────────────────────────────┐
│                         EKS Cluster                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │  backend-users pod  │    │  backend-posts pod  │             │
│  │                     │    │                     │             │
│  │  ServiceAccount:    │    │  ServiceAccount:    │             │
│  │  backend-users      │    │  backend-posts      │             │
│  └──────────┬──────────┘    └──────────┬──────────┘             │
│             │                          │                         │
│             ▼                          ▼                         │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │ IAM Role:           │    │ IAM Role:           │             │
│  │ backend-users-role  │    │ backend-posts-role  │             │
│  │                     │    │                     │             │
│  │ Permissions:        │    │ Permissions:        │             │
│  │ • SecretsManager    │    │ • SecretsManager    │             │
│  │ • SES               │    │   (different scope) │             │
│  └─────────────────────┘    └─────────────────────┘             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Files to Create

```
modules/eks-irsa/
├── main.tf              # IRSA roles for each service
├── policies.tf          # IAM policies (SecretsManager, SES)
├── variables.tf         # Input variables
├── outputs.tf           # Role ARNs for Kubernetes annotations
└── versions.tf          # Provider versions

environments/prod/eks-irsa/
└── terragrunt.hcl       # Terragrunt wrapper
```

---

## IAM Policies

### 1. Secrets Manager Read Policy

```hcl
resource "aws_iam_policy" "secrets_read" {
  name        = "${var.cluster_name}-secrets-read"
  description = "Allow reading secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:rds/*",
          "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:cache/*"
        ]
      }
    ]
  })
}
```

### 2. SES Send Policy

```hcl
resource "aws_iam_policy" "ses_send" {
  name        = "${var.cluster_name}-ses-send"
  description = "Allow sending emails via SES"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendEmail"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.ses_from_addresses
          }
        }
      }
    ]
  })
}
```

---

## IRSA Roles

### Using terraform-aws-modules/iam

```hcl
# modules/eks-irsa/main.tf

module "irsa_backend_users" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-backend-users"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:backend-users"]
    }
  }

  role_policy_arns = {
    secrets_manager = aws_iam_policy.secrets_read.arn
    ses             = aws_iam_policy.ses_send.arn
  }

  tags = var.common_tags
}

module "irsa_backend_posts" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-backend-posts"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:backend-posts"]
    }
  }

  role_policy_arns = {
    secrets_manager = aws_iam_policy.secrets_read.arn
    # No SES for posts service
  }

  tags = var.common_tags
}
```

---

## Variables

```hcl
# modules/eks-irsa/variables.tf

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where services run"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "ses_from_addresses" {
  description = "Allowed SES sender addresses"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
```

---

## Outputs

```hcl
# modules/eks-irsa/outputs.tf

output "backend_users_role_arn" {
  description = "IAM role ARN for backend-users service"
  value       = module.irsa_backend_users.iam_role_arn
}

output "backend_posts_role_arn" {
  description = "IAM role ARN for backend-posts service"
  value       = module.irsa_backend_posts.iam_role_arn
}
```

---

## Terragrunt Configuration

```hcl
# environments/prod/eks-irsa/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/eks-irsa"
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name      = include.env.locals.cluster_name
  oidc_provider_arn = dependency.eks_cluster.outputs.oidc_provider_arn
  namespace         = include.env.locals.environment
  aws_region        = include.env.locals.aws_region
  account_id        = "909561835411"

  ses_from_addresses = [
    "noreply@yourdomain.com"
  ]
}
```

---

## Kubernetes ServiceAccount Configuration

After Terraform creates the IRSA roles, annotate your ServiceAccounts in the Kubernetes deployments:

```yaml
# In backend-deployment repo

apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-users
  namespace: prod
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::909561835411:role/backend-backend-users
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-posts
  namespace: prod
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::909561835411:role/backend-backend-posts
```

Then reference it in the Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-users
  namespace: prod
spec:
  template:
    spec:
      serviceAccountName: backend-users  # Uses IRSA role
      containers:
        - name: backend-users
          # ...
```

---

## How It Works

1. **Pod starts** with `serviceAccountName: backend-users`
2. **AWS SDK** in the pod detects `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` (injected by EKS)
3. SDK calls **STS AssumeRoleWithWebIdentity** using the OIDC token
4. STS validates the token against the EKS OIDC provider
5. STS returns **temporary credentials** scoped to the IAM role
6. Pod can now call **Secrets Manager** and **SES**

```
Pod → AWS SDK → STS (AssumeRoleWithWebIdentity) → Temporary Creds → Secrets Manager/SES
         ▲
         │
    OIDC Token from EKS
```

---

## Deployment Order

```yaml
1. vpc
2. eks-cluster
3. eks-irsa          # NEW - depends on eks-cluster OIDC provider
4. rds-cluster
5. rds-database-factory
6. elasticache-valkey
7. memorydb-cluster
8. eks-addons
9. kafka-cluster
10. debezium
11. ecr
```

---

## Security Group Summary

For completeness, here's the security group setup across all modules:

| Module | Inbound Rule | Source |
|--------|--------------|--------|
| `rds-cluster` | Port 5432 | EKS node security group |
| `elasticache-valkey` | Port 6379 | EKS node security group |
| `memorydb-cluster` | Port 6379 | EKS node security group |
| `kafka-cluster` | Port 9092 | EKS node security group |

All modules receive `allowed_security_group_ids` containing the EKS node SG ID from `dependency.eks_cluster.outputs.node_security_group_id`.

---

## Cost Estimate

| Resource | Cost |
|----------|------|
| IAM Roles | Free |
| IAM Policies | Free |
| STS AssumeRole calls | Free |
| **Total** | **$0/month** |

IRSA is free - you only pay for the AWS services you call (Secrets Manager, SES).

---

## Verification Plan

1. **Terraform Validation**
   ```bash
   cd environments/prod/eks-irsa
   terragrunt init && terragrunt validate && terragrunt plan
   ```

2. **Apply and Verify IAM Roles**
   ```bash
   terragrunt apply
   aws iam get-role --role-name backend-backend-users
   ```

3. **Test from Pod**
   ```bash
   # Deploy a test pod with the service account
   kubectl run irsa-test --rm -it \
     --image=amazon/aws-cli \
     --serviceaccount=backend-users \
     --namespace=prod \
     -- aws secretsmanager get-secret-value \
        --secret-id rds/prod/backend/master-credentials \
        --region ap-southeast-1
   ```

   If IRSA is working, this returns the secret. If not, you get `AccessDenied`.
