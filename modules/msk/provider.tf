terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

data "aws_secretsmanager_secret_version" "master_credentials" {
  secret_id = var.master_credentials_secret_arn
}

locals {
  master_creds      = jsondecode(data.aws_secretsmanager_secret_version.master_credentials.secret_string)
}

provider "postgresql" {
  host            = var.postgres_host
  port            = var.postgres_port
  database        = "postgres"
  username        = local.master_creds.username
  password        = local.master_creds.password
  sslmode         = "require"
  connect_timeout = 15
  superuser       = false
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
