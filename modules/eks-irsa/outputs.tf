output "role_arns" {
  description = "Map of service account name to IAM role ARN for Kubernetes annotation."
  value       = { for k, v in aws_iam_role.this : k => v.arn }
}
