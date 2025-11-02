variable "project" { type = string }
variable "env" { type = string }

variable "snippets_bucket_name" {
  type    = string
  default = ""
}

variable "snapshots_bucket_name" {
  type    = string
  default = ""
}
