include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/opensearch"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                  = "vpc-mock"
    cluster_name            = "vpc-mock-cluster-name"
    private_subnet_ids_list = ["subnet-mock-1", "subnet-mock-2"]
  }
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    node_security_group_id = "sg-mock-node"
  }
}

inputs = {
  environment  = include.env.locals.environment
  domain_name  = "backend-search-${include.env.locals.environment}"

  vpc_id       = dependency.vpc.outputs.vpc_id
  cluster_name = dependency.vpc.outputs.cluster_name
  subnet_ids   = dependency.vpc.outputs.private_subnet_ids_list

  eks_node_security_group_id = dependency.eks_cluster.outputs.node_security_group_id

  engine_version = "OpenSearch_2.13"

  # Hot nodes
  hot_instance_type   = "r6g.large.search"
  hot_instance_count  = 2
  hot_ebs_volume_size = 100
  hot_ebs_volume_type = "gp3"
  hot_ebs_iops        = 3000
  hot_ebs_throughput   = 125

  # Warm nodes
  warm_enabled        = true
  warm_instance_type  = "ultrawarm1.medium.search"
  warm_instance_count = 2

  # Cold storage
  cold_storage_enabled = true

  # Dedicated master nodes — cluster stability
  dedicated_master_enabled = true
  dedicated_master_type    = "r6g.large.search"
  dedicated_master_count   = 3

  # Zone awareness
  zone_awareness_enabled  = true
  availability_zone_count = 2

  # ISM
  ism_hot_age    = "7d"
  ism_warm_age   = "30d"
  ism_cold_age   = "90d"
  ism_delete_age = "365d"
}
