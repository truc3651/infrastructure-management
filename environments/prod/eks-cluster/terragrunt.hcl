include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/eks-cluster"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                  = "vpc-mock-id"
    cluster_name            = "vpc-mock-cluster-name"
    private_subnet_ids_list = ["subnet-mock-1", "subnet-mock-2"]
    public_subnet_ids_list  = ["subnet-mock-3", "subnet-mock-4"]
  }
}

inputs = {
  root_account_arn   = include.env.locals.root_account_arn
  environment        = include.env.locals.environment
  
  vpc_id             = dependency.vpc.outputs.vpc_id
  vpc_cluster_name   = dependency.vpc.outputs.cluster_name
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids_list
  public_subnet_ids  = dependency.vpc.outputs.public_subnet_ids_list

  min_nodes          = 1
  desired_nodes      = 1
  max_nodes          = 2
}