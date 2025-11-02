variable "project" { type = string }
variable "env" { type = string }

variable "ingest_visibility_timeout" {
  type    = number
  default = 300
}

variable "replan_visibility_timeout" {
  type    = number
  default = 120
}

variable "message_retention_seconds" {
  type    = number
  default = 345600
}
