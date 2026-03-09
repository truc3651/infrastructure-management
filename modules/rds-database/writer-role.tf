# Writer role: Can read and write data, but cannot modify schema structure
resource "random_password" "writer" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:,.<>?"
}

resource "postgresql_role" "writer" {
  name     = local.writer_username
  login    = true
  password = random_password.writer.result

  create_database = false
  create_role     = false
  superuser       = false
  replication     = false

  depends_on = [postgresql_database.this]
}

resource "postgresql_grant" "database_connect_writer" {
  database    = postgresql_database.this.name
  role        = postgresql_role.writer.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "schema_writer" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.writer.name
  schema      = each.value
  object_type = "schema"
  privileges  = ["USAGE"]

  depends_on = [
    postgresql_schema.this,
    postgresql_grant.database_connect_writer
  ]
}

resource "postgresql_grant" "tables_writer" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.writer.name
  schema      = each.value
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE"]

  depends_on = [postgresql_grant.schema_writer]
}

resource "postgresql_grant" "sequences_writer" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.writer.name
  schema      = each.value
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]

  depends_on = [postgresql_grant.schema_writer]
}

resource "postgresql_default_privileges" "tables_writer" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.migration.name
  owner       = postgresql_role.migration.name
  schema      = each.value
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE"]

  depends_on = [postgresql_grant.schema_migration]
}

resource "postgresql_default_privileges" "sequences_writer" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.migration.name
  owner       = postgresql_role.migration.name
  schema      = each.value
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]

  depends_on = [postgresql_grant.schema_migration]
}