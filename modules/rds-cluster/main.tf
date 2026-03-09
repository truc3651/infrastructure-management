locals {
  port = 5432
  database_name = "postgres"
  master_username = "postgres"
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS Aurora PostgreSQL encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-rds-kms-${var.environment}"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.cluster_name}-rds-${var.environment}"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.cluster_name}-rds-sg-${var.environment}"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow worker node pool"
    from_port       = local.port
    to_port         = local.port
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  ingress {
    description = "Allow home CIDR blocks"
    from_port   = local.port
    to_port     = local.port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-rds-sg-${var.environment}"
  }

  lifecycle {
    # create the new one before destroying the old one
    create_before_destroy = true
  }
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.cluster_name}-postgres-${var.environment}"
  description = "Subnet group for Aurora PostgreSQL"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-postgres-subnet-group-${var.environment}"
  }
}

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:,.<>?"
}

# Cluster Parameter Group
resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.cluster_name}-postgres-cluster-${var.environment}"
  family      = var.parameter_group_family

  # Logs every schema change commands (create, drop, alter, truncate, create index)
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  # Logs SQL statements take longer than 1 second
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # Enable logical replication for Debezium CDC
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.cluster_name}-postgres-cluster-pg-${var.environment}"
  }
}

# Instance Parameter Group
resource "aws_db_parameter_group" "this" {
  name        = "${var.cluster_name}-postgres-instance-${var.environment}"
  family      = var.parameter_group_family

  # Analytic extension that could query SELECT * FROM pg_stat_statements;
  # It records: query, calls, total_exec_time, mean_exec_time, rows
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = {
    Name = "${var.cluster_name}-postgres-instance-pg-${var.environment}"
  }
}

# Cluster
resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.cluster_name}-postgres-${var.environment}"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.engine_version
  database_name      = local.database_name
  master_username    = local.master_username
  master_password    = random_password.master.result
  port               = local.port

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.rds.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  # encrypt at rest
  storage_encrypted = var.storage_encrypted
  kms_key_id        = aws_kms_key.rds.arn

  backup_retention_period      = var.backup_retention_period
  # Time range when it takes daily automated snapshot, must not overlap with maintenance window
  # Pick a low traffic - there's a IO paude at snapshot start
  preferred_backup_window      = var.preferred_backup_window
  # Minor version upgrades weekly
  preferred_maintenance_window = var.preferred_maintenance_window

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # true: cannot delete by terraform or console without flip it
  deletion_protection = var.deletion_protection
  # Takes the final snapshot before deletion
  skip_final_snapshot = var.skip_final_snapshot
  # Name of pre-deletion snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.cluster_name}-postgres-${var.environment}-final-${formatdate("YYYYMMDD-hhmmss", timestamp())}"

  # true: instance class change, parameter group change apply right away, cause brief restart
  # false: changes defered to the next preferred_maintenance_window
  apply_immediately = var.apply_immediately

  tags = {
    Name = "${var.cluster_name}-postgres-${var.environment}"
  }

  lifecycle {
    # timestamp changes every terraform plan
    ignore_changes = [
      final_snapshot_identifier,
    ]
  }
}

# Db Instances
resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.cluster_name}-postgres-${var.environment}-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_parameter_group_name = aws_db_parameter_group.this.name

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.rds.arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  tags = {
    Name = "${var.cluster_name}-postgres-${var.environment}-${count.index}"
  }
}

# Master Credentials
resource "aws_secretsmanager_secret" "master_credentials" {
  name        = "rds/${var.environment}/${var.cluster_name}/master-credentials"
  description = "Master credentials for ${var.cluster_name} Aurora PostgreSQL in ${var.environment}"
  kms_key_id  = aws_kms_key.rds.arn

  tags = {
    Name = "${var.cluster_name}-master-credentials-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "master_credentials" {
  secret_id = aws_secretsmanager_secret.master_credentials.id
  secret_string = jsonencode({
    username = local.master_username
    password = random_password.master.result
    host     = aws_rds_cluster.this.endpoint
    port     = local.port
    database = local.database_name
  })
}