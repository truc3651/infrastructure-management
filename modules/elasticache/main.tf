resource "random_password" "auth_token" {
  length  = 32
  special = false
}

resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.cluster_name}-valkey-subnet-${var.environment}"
  description = "Subnet group for ${var.cluster_name} Valkey"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-valkey-subnet-${var.environment}"
  }
}

# Records commands that exceed a configured execution time threshold (default: 10ms)
# Helps identify slow queries, inefficient access patterns, or keys with large values
resource "aws_cloudwatch_log_group" "slow_log" {
  name              = "/elasticache/${var.environment}/${var.cluster_name}/valkey/slow-log"
  retention_in_days = 7

  tags = {
    Name = "${var.cluster_name}-valkey-slow-log-${var.environment}"
  }
}

# General Valkey engine logs: startup, shutdown, replication events, failover events,
# memory warnings, and error conditions.
resource "aws_cloudwatch_log_group" "engine_log" {
  name              = "/elasticache/${var.environment}/${var.cluster_name}/valkey/engine-log"
  retention_in_days = 7

  tags = {
    Name = "${var.cluster_name}-valkey-engine-log-${var.environment}"
  }
}

resource "aws_elasticache_parameter_group" "this" {
  family      = "valkey7"
  name        = "${var.cluster_name}-valkey-params-${var.environment}"
  description = "Valkey parameters for ${var.cluster_name} cache"

  # Evict least-recently-used keys when memory is full
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  # Server-side idle connection timeout
  parameter {
    name  = "timeout"
    value = tostring(var.idle_timeout)
  }

  # TCP keepalive interval (seconds)
  parameter {
    name  = "tcp-keepalive"
    value = tostring(var.tcp_keepalive)
  }

  # Active memory defragmentation.
  # Valkey periodically reorganizes memory to reduce fragmentation caused by
  # frequent alloc/free cycles, preventing gradual memory bloat without restart.
  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  # Free evicted key memory asynchronously in a background thread
  parameter {
    name  = "lazyfree-lazy-eviction"
    value = "yes"
  }

  # Free expired key memory asynchronously in a background thread
  parameter {
    name  = "lazyfree-lazy-expire"
    value = "yes"
  }

  tags = {
    Name = "${var.cluster_name}-valkey-params-${var.environment}"
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.cluster_name}-valkey-${var.environment}"
  description          = "Valkey cache for ${var.cluster_name}"

  engine         = "valkey"
  engine_version = var.engine_version

  num_cache_clusters = var.num_cache_clusters
  node_type = var.node_type
  transit_encryption_enabled = true
  # AUTH token requires transit_encryption_enabled = true
  auth_token = random_password.auth_token.result

  automatic_failover_enabled = true
  multi_az_enabled = true

  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.valkey.id]
  parameter_group_name = aws_elasticache_parameter_group.this.name

  maintenance_window = var.maintenance_window

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = {
    Name = "${var.cluster_name}-valkey-${var.environment}"
  }
}

resource "aws_security_group" "valkey" {
  name_prefix = "${var.cluster_name}-valkey-sg-${var.environment}"
  description = "Security group for Valkey cache"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = toset(var.allowed_security_group_ids)
    content {
      description     = "Valkey from EKS nodes"
      from_port       = 6379
      to_port         = 6379
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-valkey-sg-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_secretsmanager_secret" "cache_credentials" {
  name        = "cache/${var.environment}/${var.cluster_name}/valkey-credentials"
  description = "Valkey connection credentials for ${var.cluster_name} in ${var.environment}"

  tags = {
    Name = "${var.cluster_name}-valkey-credentials-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "cache_credentials" {
  secret_id = aws_secretsmanager_secret.cache_credentials.id
  secret_string = jsonencode({
    host      = aws_elasticache_replication_group.this.primary_endpoint_address
    port      = "6379"
    password  = random_password.auth_token.result
    tlsEnabled = "true"
  })
}
