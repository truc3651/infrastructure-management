resource "aws_kms_key" "opensearch" {
  description             = "KMS key for OpenSearch domain encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.cluster_name}-opensearch-kms-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "opensearch" {
  name          = "alias/${var.cluster_name}-opensearch-${var.environment}"
  target_key_id = aws_kms_key.opensearch.key_id
}

resource "aws_security_group" "opensearch" {
  name_prefix = "${var.cluster_name}-opensearch-sg-${var.environment}"
  description = "Security group for OpenSearch domain"
  vpc_id      = var.vpc_id

  ingress {
    description     = "EKS worker nodes to OpenSearch (HTTPS)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.cluster_name}-opensearch-sg-${var.environment}"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Register endpoints in Route 53 for domain DNS
# Write service logs to CloudWatch
# Perform automated snapshots to S3
resource "aws_iam_service_linked_role" "opensearch" {
  aws_service_name = "opensearchservice.amazonaws.com"
  description      = "Service-linked role for OpenSearch"

  # Only create once per account
  count = var.environment == "prod" ? 1 : 0
}

resource "aws_cloudwatch_log_group" "opensearch_index_slow" {
  name              = "/aws/opensearch/${var.domain_name}/index-slow-logs"
  retention_in_days = 30

  tags = {
    Name        = "${var.domain_name}-index-slow-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "opensearch_search_slow" {
  name              = "/aws/opensearch/${var.domain_name}/search-slow-logs"
  retention_in_days = 30

  tags = {
    Name        = "${var.domain_name}-search-slow-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "opensearch_error" {
  name              = "/aws/opensearch/${var.domain_name}/error-logs"
  retention_in_days = 30

  tags = {
    Name        = "${var.domain_name}-error-logs"
    Environment = var.environment
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "${var.domain_name}-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "es.amazonaws.com"
        }
        Action = [
          "logs:PutLogEvents",
          "logs:PutLogEventsBatch",
          "logs:CreateLogStream"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/opensearch/${var.domain_name}/*"
      }
    ]
  })
}

resource "aws_opensearch_domain" "this" {
  domain_name    = var.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type  = var.hot_instance_type
    instance_count = var.hot_instance_count

    dedicated_master_enabled = var.dedicated_master_enabled
    dedicated_master_type    = var.dedicated_master_type
    dedicated_master_count   = var.dedicated_master_count

    warm_enabled = var.warm_enabled
    warm_type    = var.warm_enabled ? var.warm_instance_type : null
    warm_count   = var.warm_enabled ? var.warm_instance_count : null

    cold_storage_options {
      enabled = var.cold_storage_enabled
    }

    zone_awareness_enabled = var.zone_awareness_enabled

    dynamic "zone_awareness_config" {
      for_each = var.zone_awareness_enabled ? [1] : []
      content {
        availability_zone_count = var.availability_zone_count
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.hot_ebs_volume_size
    volume_type = var.hot_ebs_volume_type
    iops        = var.hot_ebs_iops
    throughput  = var.hot_ebs_throughput
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.opensearch.arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  vpc_options {
    subnet_ids         = slice(var.subnet_ids, 0, var.availability_zone_count)
    security_group_ids = [aws_security_group.opensearch.id]
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true

    master_user_options {
      master_user_name     = "admin"
      master_user_password = random_password.master_password.result
    }
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_index_slow.arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_search_slow.arn
    log_type                 = "SEARCH_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_error.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  tags = {
    Name        = var.domain_name
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_resource_policy.opensearch]
}
