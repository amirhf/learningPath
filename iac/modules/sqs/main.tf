resource "aws_sqs_queue" "ingest_dlq" {
  name                      = "${var.project}-${var.env}-ingest-dlq"
  message_retention_seconds = var.message_retention_seconds
}

resource "aws_sqs_queue" "replan_dlq" {
  name                      = "${var.project}-${var.env}-replan-dlq"
  message_retention_seconds = var.message_retention_seconds
}

resource "aws_sqs_queue" "ingest" {
  name                      = "${var.project}-${var.env}-ingest"
  visibility_timeout_seconds = var.ingest_visibility_timeout
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ingest_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "replan" {
  name                      = "${var.project}-${var.env}-replan"
  visibility_timeout_seconds = var.replan_visibility_timeout
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.replan_dlq.arn
    maxReceiveCount     = 5
  })
}

output "ingest_queue_url" {
  value = aws_sqs_queue.ingest.id
}

output "replan_queue_url" {
  value = aws_sqs_queue.replan.id
}

