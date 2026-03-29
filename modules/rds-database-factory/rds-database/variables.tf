variable "environment" {
  type        = string
}

variable "cluster_endpoint" {
  type        = string
}

variable "reader_endpoint" {
  type        = string
}

variable "master_credentials_secret_arn" {
  type        = string
}

variable "kms_key_arn" {
  type        = string
}

variable "application_name" {
  type        = string
}

variable "database_name" {
  type        = string
}

variable "schema_names" {
  type        = list(string)
  default     = ["public"]
}