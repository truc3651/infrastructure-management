resource "aws_security_group" "msk_connect" {
  name_prefix = "${var.cluster_name}-msk-connect-sg-"
  description = "Security group for MSK Connect Debezium workers"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MSK Connect workers to RDS PostgreSQL"
    from_port       = var.postgres_port
    to_port         = var.postgres_port
    protocol        = "tcp"
    security_groups = [var.rds_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.cluster_name}-msk-connect-sg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# MSK Connect Service Execution Role
resource "aws_iam_role" "msk_connect" {
  name = "${var.cluster_name}-msk-connect"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "kafkaconnect.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = {
    Name        = "${var.cluster_name}-msk-connect-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "msk_connect" {
  name = "msk-connect-policy"
  role = aws_iam_role.msk_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MSKClusterAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteDataIdempotently",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DeleteTopic",
        ]
        Resource = [
          aws_msk_cluster.this.arn,
          "${aws_msk_cluster.this.arn}/*",
        ]
      },
      {
        Sid    = "S3PluginAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.msk_plugins.arn,
          "${aws_s3_bucket.msk_plugins.arn}/*",
        ]
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          var.master_credentials_secret_arn,
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:msk-connect/${var.environment}/*",
        ]
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = [
          aws_kms_key.msk.arn,
          var.rds_kms_key_arn,
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/msk/connect/*"
      },
    ]
  })
}

# Worker logs
resource "aws_cloudwatch_log_group" "msk_connect" {
  name              = "/aws/msk/connect/${var.cluster_name}"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.msk.arn

  tags = {
    Name        = "${var.cluster_name}-msk-connect-logs"
    Environment = var.environment
  }
}

# MSK Connect Connector
resource "aws_mskconnect_connector" "cdc" {
  for_each = var.cdc_connectors

  name = each.key
  kafkaconnect_version = "2.7.1"

  capacity {
    provisioned_capacity {
      mcu_count    = 1
      worker_count = 1
    }
  }

  connector_configuration = {
    "connector.class" = "io.debezium.connector.postgresql.PostgresConnector"
    "tasks.max"       = "1" # PostgreSQL logical replication only supports 1 task per slot

    "database.hostname" = var.postgres_host
    "database.port"     = tostring(var.postgres_port)
    "database.user"     = postgresql_role.debezium[each.key].name
    "database.password" = random_password.debezium[each.key].result
    "database.dbname"   = each.value.database_name

    # Events land at {topic_prefix}.{schema}.{table}
    "topic.prefix"        = each.value.topic_prefix
    "schema.include.list" = each.value.schema_name
    "table.include.list"  = join(",", each.value.table_include_list)

    "plugin.name"                 = "pgoutput"
    "slot.name"                   = each.value.slot_name
    "publication.name"            = each.value.publication_name
    "publication.autocreate.mode" = "filtered"

    # Capture existing rows before streaming new changes
    "snapshot.mode" = "initial"

    # If tables are quiet too long, Debezium has nothing to ack, Postgresql can't clean WAL, disk fills up
    # Fix: every 10s Debezium sends a heartbeat to advance the replication slot and allow Postgresql to clean up old WAL files
    "heartbeat.interval.ms" = "10000"
    # Serialize decimal numbers as strings
    "decimal.handling.mode" = "string"
    # Format for time, date, timestamp
    "time.precision.mode"   = "connect"
    # PostgreSQL delete = Kafka same key but value null
    "tombstones.on.delete" = "true"

    "errors.tolerance"            = "none"
    "errors.log.enable"           = "true"
    "errors.log.include.messages" = "true"

    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    # JSON converter default embeds the full schema definition in every message
    # which makes 10x actual payload
    "key.converter.schemas.enable"   = "false"
    "value.converter.schemas.enable" = "false"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.this.bootstrap_brokers_tls

      vpc {
        security_groups = [aws_security_group.msk_connect.id]
        subnets         = var.subnet_ids
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.debezium.arn
      revision = aws_mskconnect_custom_plugin.debezium.latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_connect.name
      }
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect.arn

  depends_on = [
    aws_iam_role_policy.msk_connect,
    postgresql_grant.debezium_tables_select,
    aws_secretsmanager_secret_version.connector_credentials,
  ]
}
