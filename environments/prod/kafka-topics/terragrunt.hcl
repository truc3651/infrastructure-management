include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/kafka-topics"
}

dependency "msk" {
  config_path = "../msk"

  mock_outputs = {
    bootstrap_brokers_tls = "mock-broker:9094"
  }
}

inputs = {
  environment       = include.env.locals.environment
  bootstrap_servers = split(",", dependency.msk.outputs.bootstrap_brokers_tls)

  num_partitions     = 2
  replication_factor = 2
  retention_ms       = 604800000 # 7 days
}
