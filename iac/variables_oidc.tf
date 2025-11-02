variable "oidc_enable" {
  type    = bool
  default = false
}

variable "oidc_allowed_subjects" {
  type    = list(string)
  default = []
}
