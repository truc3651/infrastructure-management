include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/vpc"
}

inputs = {
  vpc_cidr = "10.0.0.0/16"

  public_subnets = {
    az1 = {
      cidr_block        = "10.0.1.0/24"
      availability_zone = "ap-southeast-1a"
    }
    az2 = {
      cidr_block        = "10.0.2.0/24"
      availability_zone = "ap-southeast-1b"
    }
  }

  private_subnets = {
    az1 = {
      cidr_block        = "10.0.11.0/24"
      availability_zone = "ap-southeast-1a"
    }
    az2 = {
      cidr_block        = "10.0.12.0/24"
      availability_zone = "ap-southeast-1b"
    }
  }

  enable_nat_gateway = include.env.locals.enable_nat_gateway
  single_nat_gateway = include.env.locals.single_nat_gateway
}
