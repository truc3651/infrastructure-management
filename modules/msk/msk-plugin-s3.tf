resource "aws_s3_bucket" "msk_plugins" {
  bucket = "${var.cluster_name}-msk-plugins-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.cluster_name}-msk-plugins"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "msk_plugins" {
  bucket = aws_s3_bucket.msk_plugins.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "msk_plugins" {
  bucket = aws_s3_bucket.msk_plugins.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.msk.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "msk_plugins" {
  bucket                  = aws_s3_bucket.msk_plugins.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Debezium Plugin — Download, Package, and Register with MSK Connect
locals {
  debezium_final_version   = "${var.debezium_version}.Final"
  debezium_plugin_zip_key  = "debezium-connector-postgres-${var.debezium_version}.zip"
  debezium_plugin_download_url = "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/${local.debezium_final_version}/debezium-connector-postgres-${local.debezium_final_version}-plugin.tar.gz"
}

resource "null_resource" "upload_debezium_plugin" {
  triggers = {
    version = var.debezium_version
    bucket  = aws_s3_bucket.msk_plugins.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      TMP_DIR=$(mktemp -d)
      curl -fsSL "${local.debezium_plugin_download_url}" -o "$TMP_DIR/debezium.tar.gz"
      mkdir -p "$TMP_DIR/plugin"
      tar -xzf "$TMP_DIR/debezium.tar.gz" -C "$TMP_DIR/plugin"
      (cd "$TMP_DIR/plugin" && zip -r "$TMP_DIR/${local.debezium_plugin_zip_key}" .)
      aws s3 cp "$TMP_DIR/${local.debezium_plugin_zip_key}" "s3://${aws_s3_bucket.msk_plugins.id}/${local.debezium_plugin_zip_key}"
      rm -rf "$TMP_DIR"
    EOT
  }

  depends_on = [
    aws_s3_bucket.msk_plugins,
    aws_s3_bucket_server_side_encryption_configuration.msk_plugins,
  ]
}

# Registers the uploaded ZIP with MSK Connect
resource "aws_mskconnect_custom_plugin" "debezium" {
  name         = "debezium-postgres-${var.environment}"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.msk_plugins.arn
      file_key   = local.debezium_plugin_zip_key
    }
  }

  depends_on = [null_resource.upload_debezium_plugin]
}