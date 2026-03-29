# Encryption at Rest
resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK cluster encryption at rest"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
  }
}

resource "aws_kms_alias" "msk" {
  name          = "alias/${var.cluster_name}"
  target_key_id = aws_kms_key.msk.key_id
}

# Cluster Config
resource "aws_msk_configuration" "this" {
  name           = var.cluster_name
  kafka_versions = [var.kafka_version]

  server_properties = <<-EOT
    auto.create.topics.enable=${var.auto_create_topics}
    num.partitions=${var.num_partitions}
    default.replication.factor=${var.num_replication_factor}
    min.insync.replicas=${var.num_min_insync_replicas}
    log.retention.hours=${var.log_retention_hours}
    log4j.logger.kafka=INFO
    log4j.logger.kafka.controller=INFO
    log4j.logger.state.change.logger=INFO
    log4j.logger.kafka.log.LogCleaner=INFO
    log4j.logger.kafka.request.logger=ERROR
  EOT
}

# Security Group
resource "aws_security_group" "msk" {
  name_prefix = var.cluster_name
  description = "Security group for MSK cluster"
  vpc_id      = var.vpc_id

  # EKS worker nodes → MSK (TLS port 9094)
  # Allows pods running on EKS to produce/consume from MSK topics.
  ingress {
    description     = "EKS worker nodes to MSK (TLS)"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  ingress {
    description     = "MSK Connect workers to MSK (TLS)"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.msk_connect.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# MSK Cluster
resource "aws_msk_cluster" "this" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.num_of_broker_nodes

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_volume_size
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn

    encryption_in_transit {
      # Reject plaintext client connections; TLS-only (port 9094).
      client_broker = "TLS"
      # Encrypt inter-broker replication traffic as well.
      in_cluster = true
    }
  }

  # Expose JMX and node-exporter endpoints inside the VPC so Prometheus
  # Grafana can scrape cluster and consumer-lag metrics without going through CloudWatch
  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  # PER_TOPIC_PER_BROKER enables MaxOffsetLag / EstimatedMaxTimeLag metrics
  # per (topic, broker) pair in CloudWatch — necessary for consumer lag alarms.
  enhanced_monitoring = "PER_TOPIC_PER_BROKER"

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
  }

  depends_on = [aws_msk_configuration.this]
}
