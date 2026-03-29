variable "environment" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for trust policy."
  type        = string
}

variable "oidc_provider" {
  description = "EKS OIDC provider URL (e.g. https://oidc.eks.region.amazonaws.com/id/XXXX)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where application pods run."
  type        = string
}

variable "service_accounts" {
  description = "Map of Kubernetes service account names to their IAM policy configuration."
  type = map(object({
    ses_enabled         = optional(bool, false)
    ses_from_addresses  = optional(list(string), [])
  }))
}

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARN patterns the pods can read (e.g. arn:aws:secretsmanager:*:*:secret:rds/*)."
  type        = list(string)
}

variable "kms_key_arns" {
  description = "KMS key ARNs used to encrypt secrets. Pods need kms:Decrypt to read encrypted secrets."
  type        = list(string)
  default     = []
}

variable "msk_cluster_arn" {
  description = "MSK cluster ARN for kafka:* permissions."
  type        = string
  default     = ""
}
