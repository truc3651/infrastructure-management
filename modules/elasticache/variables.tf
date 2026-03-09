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

variable "num_cache_clusters" {
  type        = number
  default     = 2
}

variable "node_type" {
  type        = string
}

variable "engine_version" {
  type        = string
}

variable "idle_timeout" {
  type        = number
}

variable "tcp_keepalive" {
  type        = number
}

variable "maintenance_window" {
  type        = string
}