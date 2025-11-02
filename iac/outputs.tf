output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "rds_endpoint" {
  value = module.rds.rds_endpoint
}

output "s3_snippets_bucket" {
  value = module.s3.snippets_bucket_name
}

output "s3_snapshots_bucket" {
  value = module.s3.snapshots_bucket_name
}

output "sqs_ingest_url" {
  value = module.sqs.ingest_queue_url
}

output "sqs_replan_url" {
  value = module.sqs.replan_queue_url
}

output "qdrant_log_group" {
  value = module.qdrant.log_group_name
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "oidc_role_arn" {
  value       = module.oidc.role_arn
  description = "GitHub Actions OIDC role ARN (null if disabled)"
}
