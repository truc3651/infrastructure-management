output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

# EKS OIDC endpoint
output "oidc_provider" {
  value = module.eks.oidc_provider
}

output "node_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.node.id
}