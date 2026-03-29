output "cluster_endpoint" {
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  value       = aws_rds_cluster.this.reader_endpoint
}

output "master_credentials_secret_arn" {
  value       = aws_secretsmanager_secret.master_credentials.arn
}

output "kms_key_arn" {
  value       = aws_kms_key.rds.arn
}

output "cluster_port" {
  value = aws_rds_cluster.this.port
}

output "security_group_id" {
  description = "Security group ID of the RDS cluster (add ingress rules to grant external access)."
  value       = aws_security_group.rds.id
}