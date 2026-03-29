data "aws_secretsmanager_secret_version" "master_credentials" {
  secret_id = var.master_credentials_secret_arn
}

locals {
  master_database_name = "postgres"
  master_creds = jsondecode(data.aws_secretsmanager_secret_version.master_credentials.secret_string)
  
  port               = 5432
  writer_username    = "${var.application_name}_writer"
  reader_username    = "${var.application_name}_reader"
  migration_username = "${var.application_name}_migration"
}


provider "postgresql" {
  host            = var.cluster_endpoint
  port            = var.cluster_port
  database        = local.master_database_name
  username        = local.master_creds.username
  password        = local.master_creds.password
  sslmode         = "require"
  connect_timeout = 15
  superuser       = false
}

resource "postgresql_database" "this" {
  name              = var.database_name
  owner             = local.master_creds.username
  encoding          = "UTF8"
  lc_collate        = "en_US.UTF-8"
  lc_ctype          = "en_US.UTF-8"
  connection_limit  = -1 # Unlimited connections
  allow_connections = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "postgresql_schema" "this" {
  for_each = toset(var.schema_names)

  name     = each.value
  database = postgresql_database.this.name
  owner    = local.master_creds.username

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [postgresql_database.this]
}

resource "aws_secretsmanager_secret" "credentials" {
  name        = "postgresql/${var.environment}/${var.application_name}"
  description = "Database credentials for ${var.application_name} application in ${var.environment}"
  kms_key_id  = var.kms_key_arn

  tags = {
    Name        = "${var.application_name}-db-credentials-${var.environment}"
    Application = var.application_name
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "credentials" {
  secret_id = aws_secretsmanager_secret.credentials.id
  secret_string = jsonencode({
    # Writer
    host_writer     = var.cluster_endpoint
    username_writer = postgresql_role.writer.name
    password_writer = random_password.writer.result

    # Reader
    host_reader     = var.reader_endpoint
    username_reader = postgresql_role.reader.name
    password_reader = random_password.reader.result

    # Migration
    host_migration     = var.cluster_endpoint
    username_migration = postgresql_role.migration.name
    password_migration = random_password.migration.result

    # Common details
    database = postgresql_database.this.name
    port     = local.port
    schemas  = var.schema_names
  })
}