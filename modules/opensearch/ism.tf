################################
# ISM (Index State Management) Policy
#
# Lifecycle: hot → warm → cold → delete
# - Hot:  Active indexing and search (fast SSD nodes)
# - Warm: Read-only, older data (cost-optimized UltraWarm nodes)
# - Cold: Rarely accessed, cheapest (S3-backed cold storage)
# - Delete: Data removed after retention period
################################

resource "aws_opensearch_domain_policy" "this" {
  domain_name = aws_opensearch_domain.this.domain_name

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "${aws_opensearch_domain.this.arn}/*"
      }
    ]
  })
}

# ISM policy applied via a null_resource provisioner
# because the AWS provider does not have a native ISM resource
resource "null_resource" "ism_policy" {
  triggers = {
    domain_endpoint  = aws_opensearch_domain.this.endpoint
    ism_hot_age      = var.ism_hot_age
    ism_warm_age     = var.ism_warm_age
    ism_cold_age     = var.ism_cold_age
    ism_delete_age   = var.ism_delete_age
    warm_enabled     = var.warm_enabled
    cold_enabled     = var.cold_storage_enabled
  }

  provisioner "local-exec" {
    # spotless:off
    command = <<-EOT
      curl -s -XPUT "https://${aws_opensearch_domain.this.endpoint}/_plugins/_ism/policies/data-lifecycle-policy" \
        -u "admin:${random_password.master_password.result}" \
        -H "Content-Type: application/json" \
        -d '${jsonencode({
          policy = {
            description = "Hot-Warm-Cold-Delete lifecycle policy"
            default_state = "hot"
            states = concat(
              [
                {
                  name = "hot"
                  actions = [
                    {
                      replica_count = {
                        number_of_replicas = 1
                      }
                    }
                  ]
                  transitions = var.warm_enabled ? [
                    {
                      state_name = "warm"
                      conditions = {
                        min_index_age = var.ism_hot_age
                      }
                    }
                  ] : (var.cold_storage_enabled ? [
                    {
                      state_name = "cold"
                      conditions = {
                        min_index_age = var.ism_hot_age
                      }
                    }
                  ] : [
                    {
                      state_name = "delete"
                      conditions = {
                        min_index_age = var.ism_delete_age
                      }
                    }
                  ])
                }
              ],
              var.warm_enabled ? [
                {
                  name = "warm"
                  actions = [
                    {
                      warm_migration = {}
                    },
                    {
                      replica_count = {
                        number_of_replicas = 0
                      }
                    }
                  ]
                  transitions = var.cold_storage_enabled ? [
                    {
                      state_name = "cold"
                      conditions = {
                        min_index_age = var.ism_warm_age
                      }
                    }
                  ] : [
                    {
                      state_name = "delete"
                      conditions = {
                        min_index_age = var.ism_delete_age
                      }
                    }
                  ]
                }
              ] : [],
              var.cold_storage_enabled ? [
                {
                  name = "cold"
                  actions = [
                    {
                      cold_migration = {
                        timestamp_field = "@timestamp"
                      }
                    }
                  ]
                  transitions = [
                    {
                      state_name = "delete"
                      conditions = {
                        min_index_age = var.ism_cold_age
                      }
                    }
                  ]
                }
              ] : [],
              [
                {
                  name = "delete"
                  actions = [
                    {
                      cold_delete = {}
                    }
                  ]
                  transitions = []
                }
              ]
            )
            ism_template = [
              {
                index_patterns = ["posts*", "users*"]
                priority       = 100
              }
            ]
          }
        })}'
    EOT
    # spotless:on
  }

  depends_on = [aws_opensearch_domain.this]
}
