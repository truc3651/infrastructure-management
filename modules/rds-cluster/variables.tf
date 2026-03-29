variable "environment" {
  type        = string
}

variable "aws_region" {
  type        = string
}

variable "vpc_id" {
  type        = string
}

variable "cluster_name" {
  type        = string
}

variable "private_subnet_ids" {
  type        = list(string)
}

variable "public_subnet_ids" {
  type        = list(string)
}

variable "allowed_security_group_ids" {
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  type        = list(string)
}

variable "parameter_group_family" {
  type        = string
}

variable "engine_version" {
  type        = string
}

variable "instance_class" {
  type        = string
}

variable "instance_count" {
  type        = number
}

variable "deletion_protection" {
  type        = bool
}

variable "skip_final_snapshot" {
  type        = bool
}

variable "storage_encrypted" {
  type        = bool
}

variable "backup_retention_period" {
  type        = number
}

variable "performance_insights_enabled" {
  type        = bool
}

variable "performance_insights_retention_period" {
  type        = number
}

variable "auto_minor_version_upgrade" {
  type        = bool
}

variable "apply_immediately" {
  type        = bool
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
}

variable "preferred_backup_window" {
  type        = string
}

variable "preferred_maintenance_window" {
  type        = string
}

variable "idle_in_transaction_session_timeout" {
  type        = string
}