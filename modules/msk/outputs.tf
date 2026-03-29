output "bootstrap_brokers_tls" {
  value = aws_msk_cluster.this.bootstrap_brokers_tls
}

output "bootstrap_brokers_plaintext" {
  value = aws_msk_cluster.this.bootstrap_brokers
}

output "cluster_arn" {
  value = aws_msk_cluster.this.arn
}

output "bootstrap_secret_arn" {
  value = aws_secretsmanager_secret.bootstrap_brokers.arn
}
