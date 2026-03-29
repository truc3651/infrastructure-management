resource "aws_keyspaces_keyspace" "this" {
  for_each = var.keyspaces

  name = each.key

  tags = {
    Name = "${var.cluster_name}-keyspace-${each.key}"
  }
}

locals {
  tables = merge([
    for ks_name, ks in var.keyspaces : {
      for tbl_name, tbl in ks.tables :
      "${ks_name}/${tbl_name}" => merge(tbl, { keyspace_name = ks_name })
    }
  ]...)
}

resource "aws_keyspaces_table" "this" {
  for_each = local.tables

  keyspace_name = aws_keyspaces_keyspace.this[each.value.keyspace_name].name
  table_name    = split("/", each.key)[1]

  schema_definition {
    dynamic "column" {
      for_each = each.value.columns
      content {
        name = column.value.name
        type = column.value.type
      }
    }

    dynamic "partition_key" {
      for_each = each.value.partition_key
      content {
        name = partition_key.value
      }
    }

    dynamic "clustering_key" {
      for_each = each.value.clustering_key
      content {
        name     = clustering_key.value.name
        order_by = clustering_key.value.order_by
      }
    }
  }

  capacity_specification {
    throughput_mode    = each.value.throughput_mode
    read_capacity_units  = each.value.throughput_mode == "PROVISIONED" ? each.value.read_capacity : null
    write_capacity_units = each.value.throughput_mode == "PROVISIONED" ? each.value.write_capacity : null
  }

  default_time_to_live = each.value.default_ttl

  point_in_time_recovery {
    status = each.value.point_in_time_recovery ? "ENABLED" : "DISABLED"
  }

  tags = {
    Name = "${var.cluster_name}-keyspace-table-${split("/", each.key)[1]}"
  }
}
