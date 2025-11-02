variable "project" { type = string }
variable "env" { type = string }

variable "repositories" {
  type    = list(string)
  default = ["gateway", "rag", "ingestion"]
}
