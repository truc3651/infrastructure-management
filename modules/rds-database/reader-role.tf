# Reader role: Can only read data, no write operations allowed
resource "random_password" "reader" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:,.<>?"
}

resource "postgresql_role" "reader" {
  name     = local.reader_username
  login    = true
  password = random_password.reader.result

  create_database = false
  create_role     = false
  superuser       = false
  replication     = false

  depends_on = [postgresql_database.this]
}

resource "postgresql_grant" "database_connect_reader" {
  database    = postgresql_database.this.name
  role        = postgresql_role.reader.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "schema_reader" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.reader.name
  schema      = each.value
  object_type = "schema"
  privileges  = ["USAGE"]

  depends_on = [
    postgresql_schema.this,
    postgresql_grant.database_connect_reader
  ]
}

resource "postgresql_grant" "tables_reader" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.reader.name
  schema      = each.value
  object_type = "table"
  privileges  = ["SELECT"]

  depends_on = [postgresql_grant.schema_reader]
}

resource "postgresql_grant" "sequences_reader" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.reader.name
  schema      = each.value
  object_type = "sequence"
  privileges  = ["SELECT"]

  depends_on = [postgresql_grant.schema_reader]
}

resource "postgresql_default_privileges" "tables_reader" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.migration.name
  owner       = postgresql_role.migration.name
  schema      = each.value
  object_type = "table"
  privileges  = ["SELECT"]

  depends_on = [postgresql_grant.schema_migration]
}

resource "postgresql_default_privileges" "sequences_reader" {
  for_each = toset(var.schema_names)

  database    = postgresql_database.this.name
  role        = postgresql_role.migration.name
  owner       = postgresql_role.migration.name
  schema      = each.value
  object_type = "sequence"
  privileges  = ["SELECT"]

  depends_on = [postgresql_grant.schema_migration]
}
