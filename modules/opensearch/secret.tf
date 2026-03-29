resource "random_password" "master_password" {
  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_=+"
}

resource "aws_secretsmanager_secret" "opensearch_credentials" {
  name        = "opensearch/${var.environment}/${var.domain_name}/credentials"
  description = "OpenSearch master credentials for ${var.domain_name}"
  kms_key_id  = aws_kms_key.opensearch.arn

  tags = {
    Name        = "${var.domain_name}-credentials-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "opensearch_credentials" {
  secret_id = aws_secretsmanager_secret.opensearch_credentials.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.master_password.result
    endpoint = aws_opensearch_domain.this.endpoint
  })
}