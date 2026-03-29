include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/msk"
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
    node_security_group_id = "sg-mock-node"
  }
}

dependency "rds_cluster" {
  config_path = "../rds-cluster"

  mock_outputs = {
    cluster_endpoint              = "mock-endpoint.rds.amazonaws.com"
    cluster_port                  = 5432
    master_credentials_secret_arn = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:mock"
    kms_key_arn                   = "arn:aws:kms:ap-southeast-1:123456789012:key/mock"
    security_group_id             = "sg-mock-rds"
  }
}

inputs = {
  environment  = include.env.locals.environment
  cluster_name = "msk-${include.env.locals.environment}"

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnet_ids_list

  # num_of_broker_nodes must equal the count of subnet_ids
  num_of_broker_nodes    = 2
  kafka_version          = "3.6.0"
  broker_instance_type   = "kafka.t3.small"
  broker_volume_size     = 1 # GiB, standard EBS

  auto_create_topics      = true
  num_partitions          = 2
  num_replication_factor  = 3
  num_min_insync_replicas = 2
  log_retention_hours     = 1

  eks_node_security_group_id = dependency.eks_cluster.outputs.node_security_group_id

  rds_security_group_id         = dependency.rds_cluster.outputs.security_group_id
  rds_kms_key_arn               = dependency.rds_cluster.outputs.kms_key_arn
  postgres_host                 = dependency.rds_cluster.outputs.cluster_endpoint
  postgres_port                 = dependency.rds_cluster.outputs.cluster_port
  master_credentials_secret_arn = dependency.rds_cluster.outputs.master_credentials_secret_arn

  debezium_version = "2.7.4"
  cdc_connectors = {
    "users-cdc-connector" = {
      database_name      = "users_prod"
      schema_name        = "users"
      table_include_list = ["t_friend_requests", "t_users"]
      topic_prefix       = "postgres"
      slot_name          = "debezium_users_slot"
      publication_name   = "debezium_users_publication"
    }
  }
}
