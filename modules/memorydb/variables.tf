variable "environment" {
  type        = string
}

variable "cluster_name" {
  type        = string
}

variable "aws_region" {
  type        = string
}

variable "vpc_id" {
  type        = string
}

variable "private_subnet_ids" {
  type        = list(string)
}

variable "allowed_security_group_ids" {
  type        = list(string)
}

variable "num_shards" {
  type        = number
}

variable "replicas_per_shard" {
  type        = number
}

variable "node_type" {
  type        = string
}

variable "engine_version" {
  type        = string
}

variable "tcp_keepalive" {
  type        = number
}

variable "maintenance_window" {
  type        = string
}

variable "snapshot_retention_limit" {
  type        = number
  default     = 7
}
