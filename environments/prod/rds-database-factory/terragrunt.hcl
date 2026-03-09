include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/rds-database-factory"
}

dependency "rds_cluster" {
  config_path = "../rds-cluster"

  mock_outputs = {
    cluster_endpoint               = "mock-endpoint.rds.amazonaws.com"
    reader_endpoint                = "mock-reader.rds.amazonaws.com"
    master_credentials_secret_arn  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock"
    kms_key_arn                    = "arn:aws:kms:us-east-1:123456789012:key/mock"
  }
}

inputs = {
  environment = include.env.locals.environment

  cluster_endpoint               = dependency.rds_cluster.outputs.cluster_endpoint
  reader_endpoint                = dependency.rds_cluster.outputs.reader_endpoint
  master_credentials_secret_arn  = dependency.rds_cluster.outputs.master_credentials_secret_arn
  kms_key_arn                    = dependency.rds_cluster.outputs.kms_key_arn
}