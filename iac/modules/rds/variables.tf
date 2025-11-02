variable "project" { type = string }
variable "env" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "db_name" {
  type    = string
  default = "lpdb"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "engine_version" {
  type    = string
  default = ""
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "backup_retention" {
  type    = number
  default = 7
}
