include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/eks-addons"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    public_subnet_ids_list = ["subnet-mock-3", "subnet-mock-4"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name                        = "mock-cluster"
    oidc_provider_arn                   = "arn:aws:iam::123456789012:oidc-provider/mock"
    oidc_provider                       = "https://oidc.eks.region.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  environment                        = include.env.locals.environment
  cluster_name                       = dependency.eks_cluster.outputs.cluster_name
  oidc_provider_arn                  = dependency.eks_cluster.outputs.oidc_provider_arn
  oidc_provider                      = dependency.eks_cluster.outputs.oidc_provider
  public_subnet_ids                  = dependency.vpc.outputs.public_subnet_ids_list
}