variable "project" { type = string }
variable "env" { type = string }

variable "service_name" { type = string }
variable "container_name" { type = string }
variable "image" { type = string }

variable "cluster_name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "aws_region" { type = string }

variable "cpu" {
  type = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "port" {
  type    = number
  default = 0
} # 0 means no port mapping/inbound

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "create_sg" {
  type    = bool
  default = true
}
