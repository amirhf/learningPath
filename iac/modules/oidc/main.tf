data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  enabled = var.enable && length(var.allowed_subjects) > 0
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = local.enabled ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "gh_oidc" {
  count = local.enabled ? 1 : 0
  name  = "${var.project}-${var.env}-gh-oidc-ecr"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Federated = aws_iam_openid_connect_provider.github[0].arn },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = var.allowed_subjects
        },
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecr_push" {
  count = local.enabled ? 1 : 0
  role  = aws_iam_role.gh_oidc[0].id
  name  = "${var.project}-${var.env}-ecr-push"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeRepositories",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ],
        Resource = [
          "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${var.project}-${var.env}-*"
        ]
      }
    ]
  })
}

output "role_arn" {
  value       = local.enabled ? aws_iam_role.gh_oidc[0].arn : null
  description = "GitHub Actions OIDC role ARN (null if disabled)"
}
