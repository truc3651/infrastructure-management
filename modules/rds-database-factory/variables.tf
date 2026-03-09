variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  type        = string
}

variable "reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  type        = string
}

variable "cluster_port" {
  description = "Aurora cluster port"
  type        = number
}

variable "master_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing master credentials"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting secrets"
  type        = string
}