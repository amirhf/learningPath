locals {
  name_prefix = "${var.project}-${var.env}"
  tags = {
    Project = var.project
    Env     = var.env
  }
}
