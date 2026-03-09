# Maximum offset lag across all consumer groups and partitions on this cluster
resource "aws_cloudwatch_metric_alarm" "consumer_max_offset_lag" {
  alarm_name          = "${var.cluster_name}-consumer-max-offset-lag"
  alarm_description   = "Consumer group offset lag is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MaxOffsetLag"
  namespace           = "AWS/Kafka"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_msk_cluster.this.cluster_name
  }

  tags = {
    Name        = "${var.cluster_name}-consumer-lag-alarm"
    Environment = var.environment
  }
}

# Under-replicated partitions mean a broker has fallen behind
resource "aws_cloudwatch_metric_alarm" "under_replicated_partitions" {
  alarm_name          = "${var.cluster_name}-under-replicated-partitions"
  alarm_description   = "MSK has under-replicated partitions — durability is at risk"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnderReplicatedPartitions"
  namespace           = "AWS/Kafka"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_msk_cluster.this.cluster_name
  }

  tags = {
    Name        = "${var.cluster_name}-under-replicated-alarm"
    Environment = var.environment
  }
}

# The cluster cannot coordinate partition leader elections.
resource "aws_cloudwatch_metric_alarm" "active_controller_count" {
  alarm_name          = "${var.cluster_name}-active-controller-count"
  alarm_description   = "MSK cluster has no active controller — cluster may be unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ActiveControllerCount"
  namespace           = "AWS/Kafka"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_msk_cluster.this.cluster_name
  }

  tags = {
    Name        = "${var.cluster_name}-controller-alarm"
    Environment = var.environment
  }
}

# Per-connector alarms
resource "aws_cloudwatch_metric_alarm" "msk_connect_offset_lag" {
  for_each = var.cdc_connectors

  alarm_name          = "${var.cluster_name}-${each.key}-offset-lag"
  alarm_description   = "MSK Connect connector '${each.key}' has high offset lag — CDC is behind"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "offset-lag-max"
  namespace           = "aws/msk/connect"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    "connector-name" = each.key
  }

  tags = {
    Name        = "${var.cluster_name}-${each.key}-lag-alarm"
    Environment = var.environment
  }
}
