variable "project" { type = string }
variable "env" { type = string }
variable "cluster_name" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "snapshots_bucket_name" { type = string }

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    =  number
  default = 1024
}

variable "desired_count" {
  type    = number
  default = 1
}
variable "aws_region" { type = string }

# Cloud Map service discovery
variable "service_discovery_namespace_id" {
  type = string
}

variable "service_discovery_service_name" {
  type    = string
  default = "qdrant"
}
