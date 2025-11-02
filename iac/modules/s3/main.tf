locals {
  snippets_bucket = var.snippets_bucket_name != "" ? var.snippets_bucket_name : "${var.project}-${var.env}-snippets"
  snapshots_bucket = var.snapshots_bucket_name != "" ? var.snapshots_bucket_name : "${var.project}-${var.env}-qdrant-snapshots"
}

resource "aws_s3_bucket" "snippets" {
  bucket = local.snippets_bucket
  tags = {
    Project = var.project
    Env     = var.env
  }
}

resource "aws_s3_bucket_public_access_block" "snippets" {
  bucket = aws_s3_bucket.snippets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "snippets" {
  bucket = aws_s3_bucket.snippets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "snapshots" {
  bucket = local.snapshots_bucket
  tags = {
    Project = var.project
    Env     = var.env
  }
}

resource "aws_s3_bucket_public_access_block" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

