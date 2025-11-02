variable "project" { type = string }
variable "env" { type = string }

variable "enable" {
  type    = bool
  default = false
}

# e.g. [
#   "repo:OWNER/REPO:ref:refs/heads/main",
#   "repo:OWNER/REPO:environment:prod"
# ]
variable "allowed_subjects" {
  type    = list(string)
  default = []
}
