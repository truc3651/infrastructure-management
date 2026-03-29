variable "root_account_arn" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cluster_name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "min_nodes" {
  type = number
}

variable "desired_nodes" {
  type = number
}

variable "max_nodes" {
  type = number
}
