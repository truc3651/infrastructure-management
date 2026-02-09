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
    vpc_id                  = "vpc-mock"
    private_subnet_ids_list = ["subnet-mock-1", "subnet-mock-2"]
    public_subnet_ids_list  = ["subnet-mock-3", "subnet-mock-4"]
  }
}

inputs = {
  environment        = include.env.locals.environment
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids_list
  public_subnet_ids  = dependency.vpc.outputs.public_subnet_ids_list

  min_nodes     = include.env.locals.min_nodes
  desired_nodes = include.env.locals.desired_nodes
  max_nodes     = include.env.locals.max_nodes
}