locals {
  topics = {
    # backend-graph-projector
    # "deadLetters" = {
    #   partitions         = var.num_partitions
    #   replication_factor = var.replication_factor
    #   retention_ms       = 2592000000 # 30 days
    # }
    "follows" = {
      partitions         = var.num_partitions
      replication_factor = var.replication_factor
      retention_ms       = var.retention_ms
    }
    "unfollows" = {
      partitions         = var.num_partitions
      replication_factor = var.replication_factor
      retention_ms       = var.retention_ms
    }
    "blocks" = {
      partitions         = var.num_partitions
      replication_factor = var.replication_factor
      retention_ms       = var.retention_ms
    }
    "unblocks" = {
      partitions         = var.num_partitions
      replication_factor = var.replication_factor
      retention_ms       = var.retention_ms
    }
  }
}

resource "kafka_topic" "this" {
  for_each = local.topics

  name               = each.key
  partitions         = each.value.partitions
  replication_factor = each.value.replication_factor

  config = {
    "retention.ms" = tostring(each.value.retention_ms)
  }
}
