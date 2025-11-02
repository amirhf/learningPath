variable "database_url_value" {
  description = "DATABASE_URL secret value for dev. Leave empty to create secret without version; the service will not inject the secret until a value is provided."
  type        = string
  default     = ""
}
