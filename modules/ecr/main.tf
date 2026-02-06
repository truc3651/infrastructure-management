resource "aws_ecr_repository" "repo" {
  for_each = var.service_list
  name     = each.value
}

resource "aws_ecr_lifecycle_policy" "repo_lifecycle_policy" {
  for_each   = var.service_list
  repository = each.value
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
  depends_on = [
    aws_ecr_repository.repo
  ]
}

data "aws_secretsmanager_secret" "dockerio" {
  name = "ecr-pullthroughcache/dockerhub"
}

resource "aws_ecr_pull_through_cache_rule" "dockerio" {
  credential_arn        = data.aws_secretsmanager_secret.dockerio.arn
  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
}