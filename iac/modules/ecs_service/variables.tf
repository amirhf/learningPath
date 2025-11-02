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

# Optional ALB/ingress wiring
variable "target_group_arn" {
  type    = string
  default = ""
}

variable "ingress_source_sg_id" {
  type    = string
  default = ""
}

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

# Optional inline IAM policy JSON attached to task role
variable "inline_task_policy_json" {
  type    = string
  default = ""
}

# Optional container secrets: map of env name -> Secrets Manager ARN
variable "secrets" {
  type    = map(string)
  default = {}
}

# Optional Cloud Map service registration
variable "service_discovery_service_arn" {
  type    = string
  default = ""
}
