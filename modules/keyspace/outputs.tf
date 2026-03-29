output "keyspace_arns" {
  value = { for k, v in aws_keyspaces_keyspace.this : k => v.arn }
}

output "table_arns" {
  value = { for k, v in aws_keyspaces_table.this : k => v.arn }
}
