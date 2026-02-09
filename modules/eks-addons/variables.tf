variable "environment" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider" {
  type = string
}

variable "gateway_namespace" {
  type    = string
  default = "gateway-system"
}

variable "public_subnet_ids" {
  type = list(string)
}