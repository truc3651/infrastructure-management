module "users_database" {
  source = "./rds-database"

  environment      = var.environment
  application_name = "backend-users"
  database_name    = "users_prod"
  schema_names     = ["public", "users"]

  cluster_endpoint               = var.cluster_endpoint
  reader_endpoint                = var.reader_endpoint
  master_credentials_secret_arn  = var.master_credentials_secret_arn
  kms_key_arn                    = var.kms_key_arn
}