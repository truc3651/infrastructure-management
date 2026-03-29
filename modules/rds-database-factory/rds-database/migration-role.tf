# Migration role: Can modify schema structure (DDL) and data (DML)
resource "random_password" "migrationn" {
  length  = 10
  special = false
  numeric = true
  upper   = true
  lower   = true
}

resource "postgresql_role" "migration" {
  name     = local.migration_username
  login    = true
  password = random_password.migrationn.result

  create_database = false
  create_role     = false
  replication     = false

  depends_on = [postgresql_database.this]
}

resource "postgresql_grant" "database_connect_migration" {
  database    = postgresql_database.this.name
  role        = postgresql_role.migration.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "schema_migration" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.migration.name
  schema      = each.value
  object_type = "schema"
  privileges  = ["CREATE", "USAGE"]

  depends_on = [
    postgresql_schema.this,
    postgresql_grant.database_connect_migration
  ]
}

resource "postgresql_grant" "tables_migration" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.migration.name
  schema      = each.value
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"]

  depends_on = [postgresql_grant.schema_migration]
}

resource "postgresql_grant" "sequences_migration" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.migration.name
  schema      = each.value
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT", "UPDATE"]

  depends_on = [postgresql_grant.schema_migration]
}