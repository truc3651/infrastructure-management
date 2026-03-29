## What This Project Is

Production-grade AWS infrastructure managed with **Terraform + Terragrunt**. Deploys a full backend stack in **ap-southeast-1** (Singapore) under AWS account **909561835411**.

## Directory Structure

```
├── Makefile                    # Bootstrap (S3 backend, IAM, OIDC, secrets)
├── terragrunt.hcl              # Root config: provider gen, remote state, default tags
├── modules/                    # Reusable Terraform modules
│   ├── vpc/                    # VPC, subnets, NAT, IGW
│   ├── eks-cluster/            # EKS control plane
│   ├── eks-addons/             # K8s operators (Helm, kubectl providers)
│   ├── eks-irsa/               # IAM Roles for Service Accounts
│   ├── elasticache/            # Valkey (Redis-compatible) cache
│   ├── memorydb/               # MemoryDB for newsfeed materialized view
│   ├── msk/                    # Managed Kafka + Debezium CDC connectors
│   ├── kafka-topics/           # Kafka topic management
│   ├── rds-cluster/            # Aurora PostgreSQL cluster
│   ├── rds-database/           # Single database + users
│   ├── rds-database-factory/   # Meta-module: multiple databases
│   ├── ecr/                    # ECR + pull-through cache
│   ├── ses/                    # SES email templates
│   └── keyspace/               # AWS Keyspaces (Cassandra)
├── environments/
│   ├── prod/                   # Production (active)
│   │   ├── env.hcl             # environment="prod", region="ap-southeast-1"
│   │   └── <component>/terragrunt.hcl
│   ├── dev/                    # Placeholder
│   └── staging/                # Placeholder
```

## Key Conventions

**Naming:**
- Module dirs: lowercase-hyphen (`rds-cluster`, `eks-irsa`)
- Resource names: `${var.cluster_name}-<service>-${var.environment}` (e.g. `backend-valkey-prod`)
- Secrets path: `{category}/{environment}/{name}` (e.g. `cache/prod/backend/valkey-credentials`)
- cluster_name = `"backend"` (from VPC module output)

**Standard module variables:** `environment`, `aws_region`, `cluster_name`, `vpc_id`, `private_subnet_ids`, `allowed_security_group_ids`

**Tags:** Auto-applied via Terragrunt default_tags: `Environment`, `ManagedBy=terragrunt`, `Component`. Resources add `Name` tag.

**Security patterns:**
- KMS key per module (7-day deletion window, rotation enabled)
- Security groups with `create_before_destroy` lifecycle
- `random_password` (length=32, special=false) stored in Secrets Manager
- TLS enabled on all data stores

**Terragrunt environment pattern:**
```hcl
include "root" { path = find_in_parent_folders() }
include "env"  { path = find_in_parent_folders("env.hcl"), expose = true }
terraform { source = "../../../modules/<name>" }
dependency "vpc" { config_path = "../vpc"; mock_outputs = { ... } }
inputs = { environment = include.env.locals.environment, ... }
```

**State:** S3 bucket `truc2001-terraform-remotes`, key `{env}/{component}/terraform.tfstate`, DynamoDB lock table `terraform-locks`

**Provider versions:** AWS ~> 5.0, Terraform >= 1.5, Kubernetes ~> 2.23, Helm ~> 2.11

**CI/CD:** GitHub Actions with OIDC federation (GitHubActionsRole), repo `truc3651/infrastructure-management`

## Dependency Chain

```
vpc → eks-cluster, rds-cluster, elasticache, memorydb, keyspace
eks-cluster → eks-addons, eks-irsa, msk
rds-cluster → rds-database-factory, msk, eks-irsa
msk → kafka-topics, eks-irsa
```

## Network

- VPC CIDR: `10.0.0.0/16`
- Public subnets: `10.0.1.0/24` (az1), `10.0.2.0/24` (az2)
- Private subnets: `10.0.11.0/24` (az1), `10.0.12.0/24` (az2)
- Single NAT gateway (cost optimization)
