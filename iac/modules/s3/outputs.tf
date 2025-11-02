output "snippets_bucket_name" {
  value = aws_s3_bucket.snippets.bucket
}

output "snapshots_bucket_name" {
  value = aws_s3_bucket.snapshots.bucket
}
