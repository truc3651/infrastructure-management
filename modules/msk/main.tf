resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK cluster encryption at rest"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/msk/*"
          }
        }
      },
    ]
  })

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
  EOT
}

resource "aws_security_group" "msk" {
  name_prefix = var.cluster_name
  description = "Security group for MSK cluster"
  vpc_id      = var.vpc_id

  # EKS worker nodes → MSK (IRSA)
  # MSK Connect workers → MSK (IAM auth)
  ingress {
    description     = "EKS worker nodes and MSK Connect workers to MSK"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.msk_connect.id, var.eks_node_security_group_id]
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

  client_authentication {
    sasl {
      iam = true
    }
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

resource "aws_secretsmanager_secret" "bootstrap_brokers" {
  name        = "msk/${var.environment}/bootstrap-brokers"
  description = "MSK bootstrap broker endpoints for ${var.cluster_name} in ${var.environment}"
  kms_key_id  = aws_kms_key.msk.arn

  tags = {
    Name        = "${var.cluster_name}-bootstrap-brokers-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "bootstrap_brokers" {
  secret_id = aws_secretsmanager_secret.bootstrap_brokers.id
  secret_string = jsonencode({
    bootstrap_brokers_tls       = aws_msk_cluster.this.bootstrap_brokers_tls
    bootstrap_brokers_plaintext = aws_msk_cluster.this.bootstrap_brokers
  })
}
