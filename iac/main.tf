// Phase 0 root module wiring (placeholders)

terraform {
  # Remote state
  backend "s3" {
    bucket         = "learning-planner"
    key            = "learning-path/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
  required_version = ">= 1.6.0"
}

# ECS services (deploy with desired_count = 0 until images are pushed)
module "service_rag" {
  source = "./modules/ecs_service"

  project        = var.project
  env            = var.env
  service_name   = "rag"
  container_name = "rag"
  image          = format("%s:latest", module.ecr.repository_urls["${var.project}-${var.env}-rag"])

  cluster_name = module.ecs.cluster_name
  subnet_ids   = module.vpc.private_subnets
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = "10.0.0.0/16"
  aws_region   = var.aws_region

  cpu            = 256
  memory         = 512
  desired_count  = 0
  port           = 8000
  env_vars       = { AWS_REGION = var.aws_region }
}

module "service_gateway" {
  source = "./modules/ecs_service"

  project        = var.project
  env            = var.env
  service_name   = "gateway"
  container_name = "gateway"
  image          = format("%s:latest", module.ecr.repository_urls["${var.project}-${var.env}-gateway"])

  cluster_name = module.ecs.cluster_name
  subnet_ids   = module.vpc.private_subnets
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = "10.0.0.0/16"
  aws_region   = var.aws_region

  cpu            = 256
  memory         = 512
  desired_count  = 0
  port           = 8080
  env_vars       = { AWS_REGION = var.aws_region }
}

module "service_ingestion" {
  source = "./modules/ecs_service"

  project        = var.project
  env            = var.env
  service_name   = "ingestion"
  container_name = "ingestion"
  image          = format("%s:latest", module.ecr.repository_urls["${var.project}-${var.env}-ingestion"])

  cluster_name = module.ecs.cluster_name
  subnet_ids   = module.vpc.private_subnets
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = "10.0.0.0/16"
  aws_region   = var.aws_region

  cpu           = 256
  memory        = 512
  desired_count = 0
  port          = 0
  env_vars      = { AWS_REGION = var.aws_region }
}

# Allow ECS services to connect to Postgres (RDS) on 5432
resource "aws_security_group_rule" "rds_from_rag" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.sg_id
  source_security_group_id = module.service_rag.sg_id
}

resource "aws_security_group_rule" "rds_from_gateway" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.sg_id
  source_security_group_id = module.service_gateway.sg_id
}

resource "aws_security_group_rule" "rds_from_ingestion" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.sg_id
  source_security_group_id = module.service_ingestion.sg_id
}

provider "aws" {
  region = var.aws_region
}

module "ecr" {
  source = "./modules/ecr"

  project = var.project
  env     = var.env
}

module "oidc" {
  source = "./modules/oidc"

  project          = var.project
  env              = var.env
  enable           = var.oidc_enable
  allowed_subjects = var.oidc_allowed_subjects
}

module "vpc" {
  source = "./modules/vpc"

  project            = var.project
  env                = var.env
  vpc_cidr           = "10.0.0.0/16"
  az_count           = 2
  single_nat_gateway = true
}

module "s3" {
  source = "./modules/s3"

  project = var.project
  env     = var.env
}

module "sqs" {
  source = "./modules/sqs"

  project = var.project
  env     = var.env
}

module "ecs" {
  source = "./modules/ecs"

  project = var.project
  env     = var.env
}

module "rds" {
  source = "./modules/rds"

  project            = var.project
  env                = var.env
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  # Cost-saving defaults
  instance_class     = "db.t4g.micro"
  multi_az           = false
  allocated_storage  = 20
  backup_retention   = 7
}

module "qdrant" {
  source = "./modules/qdrant"

  project              = var.project
  env                  = var.env
  cluster_name         = module.ecs.cluster_name
  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = "10.0.0.0/16"
  private_subnet_ids   = module.vpc.private_subnets
  snapshots_bucket_name = module.s3.snapshots_bucket_name
  aws_region           = var.aws_region

  # Cost-saving defaults
  cpu          = 512
  memory       = 1024
  desired_count = 1
}
