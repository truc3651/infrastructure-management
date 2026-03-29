data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  oidc_issuer = replace(var.oidc_provider, "https://", "")
}

resource "aws_iam_role" "this" {
  for_each = var.service_accounts

  name = "${var.cluster_name}-${each.key}-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace}:${each.key}"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Environment    = var.environment
    ServiceAccount = each.key
  }
}

resource "aws_iam_policy" "secrets_read" {
  name = "${var.cluster_name}-secrets-read-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secrets_arns
      }],
      length(var.kms_key_arns) > 0 ? [{
        Sid    = "DecryptSecrets"
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = var.kms_key_arns
      }] : []
    )
  })
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  for_each = var.service_accounts

  role       = aws_iam_role.this[each.key].name
  policy_arn = aws_iam_policy.secrets_read.arn
}

locals {
  ses_service_accounts = { for k, v in var.service_accounts : k => v if v.ses_enabled }
}

resource "aws_iam_policy" "ses_send" {
  count = length(local.ses_service_accounts) > 0 ? 1 : 0

  name = "${var.cluster_name}-ses-send-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SendEmail"
      Effect = "Allow"
      Action = [
        "ses:SendEmail",
        "ses:SendRawEmail",
        "ses:SendTemplatedEmail"
      ]
      Resource = "arn:aws:ses:${local.region}:${local.account_id}:identity/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ses_send" {
  for_each = local.ses_service_accounts

  role       = aws_iam_role.this[each.key].name
  policy_arn = aws_iam_policy.ses_send[0].arn
}

resource "aws_iam_policy" "msk" {
  count = var.msk_cluster_arn != "" ? 1 : 0

  name = "${var.cluster_name}-msk-access-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MSKDescribe"
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:DescribeClusterV2",
          "kafka:GetBootstrapBrokers"
        ]
        Resource = var.msk_cluster_arn
      },
      {
        Sid    = "MSKTopicAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup"
        ]
        Resource = [
          var.msk_cluster_arn,
          "arn:aws:kafka:${local.region}:${local.account_id}:topic/${replace(var.msk_cluster_arn, "/.*\\//", "")}/*",
          "arn:aws:kafka:${local.region}:${local.account_id}:group/${replace(var.msk_cluster_arn, "/.*\\//", "")}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "msk" {
  for_each = var.msk_cluster_arn != "" ? var.service_accounts : {}

  role       = aws_iam_role.this[each.key].name
  policy_arn = aws_iam_policy.msk[0].arn
}
