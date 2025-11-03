output "log_group_name" {
  value = aws_cloudwatch_log_group.qdrant.name
}

output "service_discovery_service_arn" {
  value = aws_service_discovery_service.this.arn
}
