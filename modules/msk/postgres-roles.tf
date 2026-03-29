resource "random_password" "debezium" {
  for_each = var.cdc_connectors

  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:,.<>?"
}

resource "postgresql_role" "debezium" {
  for_each = var.cdc_connectors

  name     = "debezium_${each.key}"
  password = random_password.debezium[each.key].result

  login           = true
  replication     = false
  create_database = false
  create_role     = false
  superuser       = false

  # Grant rds_replication role which allows logical replication slot usage.
  roles = ["rds_replication"]
}

resource "postgresql_grant" "debezium_database_connect" {
  for_each = var.cdc_connectors

  database    = each.value.database_name
  role        = postgresql_role.debezium[each.key].name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "debezium_schema_usage" {
  for_each = var.cdc_connectors

  database    = each.value.database_name
  role        = postgresql_role.debezium[each.key].name
  schema      = each.value.schema_name
  object_type = "schema"
  privileges  = ["USAGE"]

  depends_on = [postgresql_grant.debezium_database_connect]
}

resource "postgresql_grant" "debezium_tables_select" {
  for_each = var.cdc_connectors

  database    = each.value.database_name
  role        = postgresql_role.debezium[each.key].name
  schema      = each.value.schema_name
  object_type = "table"
  privileges  = ["SELECT"]

  depends_on = [postgresql_grant.debezium_schema_usage]
}

resource "aws_secretsmanager_secret" "connector_credentials" {
  for_each = var.cdc_connectors

  name        = "msk-connect/${var.environment}/${each.key}"
  description = "Debezium CDC credentials for connector '${each.key}' in ${var.environment}"
  kms_key_id  = aws_kms_key.msk.arn

  tags = {
    Name        = "${var.cluster_name}-${each.key}-credentials"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "connector_credentials" {
  for_each = var.cdc_connectors

  secret_id = aws_secretsmanager_secret.connector_credentials[each.key].id
  secret_string = jsonencode({
    username = postgresql_role.debezium[each.key].name
    password = random_password.debezium[each.key].result
    host     = var.postgres_host
    port     = var.postgres_port
    database = each.value.database_name
  })
}