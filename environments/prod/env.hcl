locals {
  environment  = "prod"
  aws_region   = "ap-southeast-1"
  cluster_name = "backend"

  enable_nat_gateway = true
  single_nat_gateway = true

  min_nodes     = 1
  desired_nodes = 1
  max_nodes     = 2
}
