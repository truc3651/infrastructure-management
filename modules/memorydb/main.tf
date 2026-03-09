resource "aws_kms_key" "memorydb" {
  description             = "KMS key for MemoryDB newsfeed cluster encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-memorydb-kms-${var.environment}"
  }
}

resource "aws_kms_alias" "memorydb" {
  name          = "alias/${var.cluster_name}-memorydb-${var.environment}"
  target_key_id = aws_kms_key.memorydb.key_id
}

# ACL
resource "random_password" "app_user_password" {
  length  = 32
  special = false
}

resource "aws_memorydb_user" "app" {
  user_name = "${var.cluster_name}-app-${var.environment}"

  #   on          → user is active
  #   ~feed:*     → can only read/write keys starting with "feed:"
  #   &*          → can publish/subscribe to all channels
  #   +@all       → all commands allowed
  #   -@dangerous → except dangerous commands (FLUSHALL, DEBUG, CONFIG RESETSTAT, etc.)
  access_string = "on ~feed:* &* +@all -@dangerous"

  authentication_mode {
    type      = "password"
    passwords = [random_password.app_user_password.result]
  }

  tags = {
    Name = "${var.cluster_name}-memorydb-user-${var.environment}"
  }
}

resource "aws_memorydb_acl" "this" {
  name       = "${var.cluster_name}-memorydb-acl-${var.environment}"
  user_names = [aws_memorydb_user.app.user_name]

  tags = {
    Name = "${var.cluster_name}-memorydb-acl-${var.environment}"
  }
}

# Cluster
resource "aws_memorydb_subnet_group" "this" {
  name        = "${var.cluster_name}-memorydb-subnet-${var.environment}"
  description = "Subnet group for ${var.cluster_name} MemoryDB"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-memorydb-subnet-${var.environment}"
  }
}

resource "aws_security_group" "memorydb" {
  name_prefix = "${var.cluster_name}-memorydb-sg-${var.environment}"
  description = "Security group for MemoryDB newsfeed cluster"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = toset(var.allowed_security_group_ids)
    content {
      description     = "MemoryDB from EKS nodes"
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
    Name = "${var.cluster_name}-memorydb-sg-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_memorydb_parameter_group" "this" {
  family      = "memorydb_redis7"
  name        = "${var.cluster_name}-memorydb-params-${var.environment}"
  description = "MemoryDB parameters for ${var.cluster_name} newsfeed cluster"

  # Evict only keys that have a TTL set, using LRU ordering
  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  # Active memory defragmentation
  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  parameter {
    name  = "tcp-keepalive"
    value = tostring(var.tcp_keepalive)
  }

  tags = {
    Name = "${var.cluster_name}-memorydb-params-${var.environment}"
  }
}

resource "aws_memorydb_cluster" "this" {
  name        = "${var.cluster_name}-newsfeed-${var.environment}"
  description = "MemoryDB cluster for ${var.cluster_name} newsfeed materialized view"

  engine_version = var.engine_version
  node_type      = var.node_type

  num_shards             = var.num_shards
  num_replicas_per_shard = var.replicas_per_shard

  acl_name             = aws_memorydb_acl.this.name
  subnet_group_name    = aws_memorydb_subnet_group.this.name
  security_group_ids   = [aws_security_group.memorydb.id]
  parameter_group_name = aws_memorydb_parameter_group.this.name

  tls_enabled = true
  kms_key_arn = aws_kms_key.memorydb.arn
  maintenance_window = var.maintenance_window
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "03:00-04:00"

  tags = {
    Name = "${var.cluster_name}-newsfeed-${var.environment}"
  }
}

# Secrets Manager
resource "aws_secretsmanager_secret" "credentials" {
  name        = "cache/${var.environment}/${var.cluster_name}/memorydb-credentials"
  description = "MemoryDB connection credentials for ${var.cluster_name} newsfeed in ${var.environment}"
  kms_key_id  = aws_kms_key.memorydb.arn

  tags = {
    Name = "${var.cluster_name}-memorydb-credentials-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "credentials" {
  secret_id = aws_secretsmanager_secret.credentials.id
  secret_string = jsonencode({
    host        = aws_memorydb_cluster.this.cluster_endpoint[0].address
    port        = tostring(aws_memorydb_cluster.this.cluster_endpoint[0].port)
    username    = aws_memorydb_user.app.user_name
    password    = random_password.app_user_password.result
    tlsEnabled  = "true"
    clusterMode = "true"
  })
}
