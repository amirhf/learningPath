aws_region = "us-east-1"
project    = "learning-path"
env        = "dev"
oidc_enable = true
oidc_allowed_subjects = [
  "repo:amirhf/learningPath:ref:refs/heads/main"
]
