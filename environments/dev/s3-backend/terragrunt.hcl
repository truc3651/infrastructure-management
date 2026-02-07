include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/s3-backend"
}

inputs = {
  bucket_name = "terraform-remotes"
  dynamodb_table_name = "terraform-locks"
  aws_region = include.env.locals.aws_region
}