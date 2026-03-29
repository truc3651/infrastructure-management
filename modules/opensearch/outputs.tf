output "domain_endpoint" {
  value = aws_opensearch_domain.this.endpoint
}

output "domain_arn" {
  value = aws_opensearch_domain.this.arn
}

output "domain_id" {
  value = aws_opensearch_domain.this.domain_id
}

output "security_group_id" {
  value = aws_security_group.opensearch.id
}

output "credentials_secret_arn" {
  value = aws_secretsmanager_secret.opensearch_credentials.arn
}

output "kms_key_arn" {
  value = aws_kms_key.opensearch.arn
}
