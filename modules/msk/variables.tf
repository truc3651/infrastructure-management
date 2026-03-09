################################################################################
# Cluster identity
################################################################################

variable "environment" {
  type = string
}

variable "cluster_name" {
  type = string
}

################################################################################
# Networking
################################################################################

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for MSK brokers and MSK Connect workers. Count must equal num_of_broker_nodes."
  type        = list(string)
}

################################################################################
# MSK Broker
################################################################################

variable "num_of_broker_nodes" {
  description = "Number of broker nodes. Must equal the count of subnet_ids."
  type        = number
}

variable "kafka_version" {
  type = string
}

variable "broker_instance_type" {
  type = string
}

variable "broker_volume_size" {
  description = "EBS volume size (GiB) per broker. Standard EBS — tiered storage is not used."
  type        = number
}

################################################################################
# Kafka topic / retention configuration
################################################################################

variable "auto_create_topics" {
  type = bool
}

variable "num_partitions" {
  description = "Default number of partitions for auto-created topics."
  type        = number
}

variable "num_replication_factor" {
  description = "Default replication factor. Must be <= num_of_broker_nodes."
  type        = number
}

variable "num_min_insync_replicas" {
  description = "Minimum in-sync replicas required for a produce to succeed."
  type        = number
}

variable "log_retention_hours" {
  type = number
}

################################################################################
# EKS connectivity
################################################################################

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS worker nodes. Granted TLS ingress to MSK (9094)."
  type        = string
}

################################################################################
# RDS connectivity (MSK Connect workers → PostgreSQL)
################################################################################

variable "rds_security_group_id" {
  description = "Security group ID of the RDS cluster. MSK Connect workers are granted ingress on 5432."
  type        = string
}

variable "rds_kms_key_arn" {
  description = "KMS key ARN used by RDS. Added to MSK Connect IAM role for KMS Decrypt."
  type        = string
}

variable "postgres_host" {
  description = "RDS cluster writer endpoint."
  type        = string
}

variable "postgres_port" {
  type = number
}

variable "master_credentials_secret_arn" {
  description = "Secrets Manager ARN for RDS master credentials (used by postgresql provider and MSK Connect IAM)."
  type        = string
}

################################################################################
# MSK Connect — Debezium plugin
################################################################################

variable "debezium_version" {
  description = "Debezium connector version without .Final suffix (e.g. '2.7.4')."
  type        = string
}

################################################################################
# CDC Connectors
#
# Each entry creates one MSK Connect connector, one PostgreSQL CDC role with
# the required grants, and one Secrets Manager secret for the credentials.
# The Debezium plugin ZIP (shared) is downloaded once from Maven Central.
#
# Key naming rules:
#   - The map key becomes the MSK Connect connector name and is used to derive
#     the PostgreSQL username: debezium_<key_with_hyphens_replaced_by_underscores>
#   - slot_name and publication_name must be unique across all connectors on
#     the same PostgreSQL instance.
#
# Example — adding a posts connector in the future:
#
#   "posts-cdc-connector" = {
#     database_name      = "posts_prod"
#     schema_name        = "posts"
#     table_include_list = ["posts_prod.t_posts", "posts_prod.t_comments"]
#     topic_prefix       = "postgres"
#     slot_name          = "debezium_posts_slot"
#     publication_name   = "debezium_posts_publication"
#   }
################################################################################

variable "cdc_connectors" {
  description = "Map of Debezium PostgreSQL CDC connectors to manage. Map key is the connector name."
  type = map(object({
    database_name      = string
    schema_name        = string
    table_include_list = list(string)
    topic_prefix       = string # events land at {prefix}.{schema}.{table}
    slot_name          = string # must be unique per PostgreSQL instance
    publication_name   = string # must be unique per PostgreSQL instance
  }))
  default = {}
}
