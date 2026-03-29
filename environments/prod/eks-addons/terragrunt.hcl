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
    cluster_name           = "vpc-mock-cluster-name"
    public_subnet_ids_list = ["subnet-mock-3", "subnet-mock-4"]
  }
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::1234567890:oidc-provider/mock"
    oidc_provider     = "https://oidc.eks.region.amazonaws.com/id/MOCK"
  }
}

inputs = {
  environment       = include.env.locals.environment

  cluster_name      = dependency.vpc.outputs.cluster_name
  public_subnet_ids = dependency.vpc.outputs.public_subnet_ids_list
  
  oidc_provider_arn = dependency.eks_cluster.outputs.oidc_provider_arn
  oidc_provider     = dependency.eks_cluster.outputs.oidc_provider

  gateway_namespace = "gateway"
}
