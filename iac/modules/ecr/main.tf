data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  repo_names = [for r in var.repositories : "${var.project}-${var.env}-${r}"]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.repo_names)

  name                 = each.key
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "retain_recent" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 10 images",
        selection = {
          tagStatus   = "any",
          countType   = "imageCountMoreThan",
          countNumber = 10
        },
        action = { type = "expire" }
      }
    ]
  })
}

output "repository_urls" {
  value = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}
