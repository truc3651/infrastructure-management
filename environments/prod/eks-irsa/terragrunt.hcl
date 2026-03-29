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

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    cluster_name = "vpc-mock-cluster-name"
  }
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/mock"
    oidc_provider     = "https://oidc.eks.region.amazonaws.com/id/MOCK"
  }
}

dependency "rds_cluster" {
  config_path = "../rds-cluster"

  mock_outputs = {
    master_credentials_secret_arn = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:mock"
    kms_key_arn                   = "arn:aws:kms:ap-southeast-1:123456789012:key/mock"
  }
}

dependency "msk" {
  config_path = "../msk"

  mock_outputs = {
    cluster_arn        = "arn:aws:kafka:ap-southeast-1:123456789012:cluster/mock/mock"
    bootstrap_secret_arn = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:mock"
  }
}

inputs = {
  environment       = include.env.locals.environment
  namespace         = include.env.locals.environment
  cluster_name      = dependency.vpc.outputs.cluster_name
  oidc_provider_arn = dependency.eks_cluster.outputs.oidc_provider_arn
  oidc_provider     = dependency.eks_cluster.outputs.oidc_provider

  service_accounts = {
    "backend-users" = {
      ses_enabled = true
    }
    "backend-posts" = {
      ses_enabled = false
    }
  }

  # Secrets the pods can read: RDS credentials, cache credentials, MSK bootstrap brokers
  secrets_arns = [
    "arn:aws:secretsmanager:${include.env.locals.aws_region}:909561835411:secret:postgresql/${include.env.locals.environment}/*",
    "arn:aws:secretsmanager:${include.env.locals.aws_region}:909561835411:secret:rds/${include.env.locals.environment}/*",
    "arn:aws:secretsmanager:${include.env.locals.aws_region}:909561835411:secret:neo4j/${include.env.locals.environment}/*",
    "arn:aws:secretsmanager:${include.env.locals.aws_region}:909561835411:secret:cache/${include.env.locals.environment}/*",
    "arn:aws:secretsmanager:${include.env.locals.aws_region}:909561835411:secret:msk/${include.env.locals.environment}/*",
  ]

  # KMS keys used to encrypt the secrets above
  kms_key_arns = [
    dependency.rds_cluster.outputs.kms_key_arn,
  ]

  msk_cluster_arn = dependency.msk.outputs.cluster_arn
}
