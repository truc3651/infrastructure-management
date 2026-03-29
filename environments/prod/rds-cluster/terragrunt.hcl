include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/rds-cluster"
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

  # Allow EKS nodes to connect to the database
  allowed_security_group_ids = [dependency.eks_cluster.outputs.node_security_group_id]
  allowed_cidr_blocks        = []

  # PostgreSQL configuration
  parameter_group_family = "aurora-postgresql16"
  engine_version         = "16.4"
  instance_class         = "db.t3.medium"
  instance_count         = 2 # 1 writer + 1 reader
  deletion_protection = false
  skip_final_snapshot = false
  storage_encrypted   = true
  backup_retention_period = 7
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  auto_minor_version_upgrade = true
  apply_immediately = false
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  preferred_backup_window = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
}
