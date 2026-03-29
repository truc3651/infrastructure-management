variable "environment" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "keyspaces" {
  type = map(object({
    replication_strategy = optional(string, "SINGLE_REGION")
    tables = optional(map(object({
      throughput_mode    = optional(string, "PAY_PER_REQUEST")
      read_capacity      = optional(number, 0)
      write_capacity     = optional(number, 0)
      default_ttl        = optional(number, 0)
      point_in_time_recovery = optional(bool, true)
      columns = list(object({
        name = string
        type = string
      }))
      partition_key = list(string)
      clustering_key = optional(list(object({
        name     = string
        order_by = string
      })), [])
    })), {})
  }))
}
