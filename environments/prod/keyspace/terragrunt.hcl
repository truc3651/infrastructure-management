include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/keyspace"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    cluster_name = "vpc-mock-cluster-name"
  }
}

inputs = {
  environment  = include.env.locals.environment
  aws_region   = include.env.locals.aws_region
  cluster_name = dependency.vpc.outputs.cluster_name

  keyspaces = {
    "prod_posts" = {
      replication_strategy = "SINGLE_REGION"
    }
  }
}
