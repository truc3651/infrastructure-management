variable "environment" {
  type = string
}

variable "bootstrap_servers" {
  type        = list(string)
}

variable "num_partitions" {
  type        = number
}

variable "replication_factor" {
  type        = number
}

variable "retention_ms" {
  type        = number
}
