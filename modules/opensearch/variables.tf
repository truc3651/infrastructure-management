variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "eks_node_security_group_id" {
  type = string
}

variable "engine_version" {
  type    = string
}

variable "domain_name" {
  type = string
}

variable "hot_instance_type" {
  type    = string
}

variable "hot_instance_count" {
  type    = number
}

variable "hot_ebs_volume_size" {
  type    = number
}

variable "hot_ebs_volume_type" {
  type    = string
}

variable "hot_ebs_iops" {
  type    = number
}

variable "hot_ebs_throughput" {
  type    = number
}

variable "warm_enabled" {
  type    = bool
}

variable "warm_instance_type" {
  type    = string
}

variable "warm_instance_count" {
  type    = number
}

variable "cold_storage_enabled" {
  type    = bool
}

variable "dedicated_master_enabled" {
  type    = bool
}

variable "dedicated_master_type" {
  type    = string
}

variable "dedicated_master_count" {
  type    = number
}

variable "zone_awareness_enabled" {
  type    = bool
}

variable "availability_zone_count" {
  type    = number
}

variable "ism_hot_age" {
  type        = string
}

variable "ism_warm_age" {
  type        = string
}

variable "ism_cold_age" {
  type        = string
}

variable "ism_delete_age" {
  type        = string
}
