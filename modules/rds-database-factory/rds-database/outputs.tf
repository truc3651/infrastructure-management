output "database_name" {
  value       = postgresql_database.this.name
}

output "credentials_secret_arn" {
  value       = aws_secretsmanager_secret.credentials.arn
}

output "credentials_secret_name" {
  value       = aws_secretsmanager_secret.credentials.name
}

output "writer_username" {
  value       = postgresql_role.writer.name
}

output "reader_username" {
  value       = postgresql_role.reader.name
}

output "migration_username" {
  value       = postgresql_role.migration.name
}

output "schemas" {
  value       = [for s in postgresql_schema.this : s.name]
}
