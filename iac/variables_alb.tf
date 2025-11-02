variable "alb_acm_certificate_arn" {
  description = "ACM certificate ARN for the public ALB. When set, creates an HTTPS listener on 443 and redirects HTTP->HTTPS. Leave empty to keep HTTP-only."
  type        = string
  default     = ""
}
