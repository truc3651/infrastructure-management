include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/elasticache"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                  = "vpc-mock"
    private_subnet_ids_list = ["subnet-mock-1", "subnet-mock-2"]
  }
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    node_security_group_id = "sg-mock"
  }
}

inputs = {
  environment  = include.env.locals.environment
  aws_region   = include.env.locals.aws_region

  vpc_id             = dependency.vpc.outputs.vpc_id
  cluster_name       = dependency.vpc.outputs.cluster_name
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids_list

  allowed_security_group_ids = [dependency.eks_cluster.outputs.node_security_group_id]

  # 1 primary + 1 replica in different AZs
  num_cache_clusters = 2
  node_type          = "cache.t4g.micro"
  engine_version     = "7.2"

  idle_timeout  = 300
  tcp_keepalive = 300
  maintenance_window = "sun:05:00-sun:06:00"
}
