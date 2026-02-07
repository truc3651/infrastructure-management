locals {
  # Parse the file path to extract environment name
  # Path will be like: environments/dev/vpc/terragrunt.hcl
  parsed = regex(".*environments/(?P<env>[^/]+)/(?P<component>[^/]+)$", get_terragrunt_dir())
  
  environment = local.parsed.env
  component   = local.parsed.component

   is_bootstrap = local.component == "s3-backend"
  
  # Common variables
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  aws_region   = local.env_vars.locals.aws_region
  cluster_name = local.env_vars.locals.cluster_name
  
  # Common tags applied to all resources
  common_tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Component   = local.component
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "${local.aws_region}"
  
  default_tags {
    tags = ${jsonencode(local.common_tags)}
  }
}
EOF
}

remote_state {
  backend = "s3"

  disable_init = local.is_bootstrap
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    bucket         = "terraform-remotes"
    key            = "${local.environment}/${local.component}/terraform.tfstate"
    region         = "${local.aws_region}"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

inputs = {
  environment  = local.environment
  aws_region   = local.aws_region
  cluster_name = local.cluster_name
  common_tags  = local.common_tags
}