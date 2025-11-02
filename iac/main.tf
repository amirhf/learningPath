// Phase 0 root module wiring (placeholders)

terraform {
  # Remote state
  required_version = ">= 1.6.0"
  backend "s3" {
    bucket         = "learning-planner"
    key            = "learning-path/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}

# Public ALB for gateway
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.env}-alb-sg"
  description = "ALB SG for public HTTP"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "gateway" {
  name               = "${var.project}-${var.env}-gateway"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "gateway" {
  name_prefix = "gw-"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/healthz"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "http_forward" {
  count             = var.alb_acm_certificate_arn == "" ? 1 : 0
  load_balancer_arn = aws_lb.gateway.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = var.alb_acm_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.gateway.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.alb_acm_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.gateway.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.alb_acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}


# Private service discovery for internal calls
resource "aws_service_discovery_private_dns_namespace" "svc" {
  name = "${var.project}.${var.env}.local"
  vpc  = module.vpc.vpc_id
}

resource "aws_service_discovery_service" "rag" {
  name = "rag"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.svc.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# Secrets Manager: DATABASE_URL
resource "aws_secretsmanager_secret" "database_url" {
  name = "${var.project}/${var.env}/DATABASE_URL"
}

resource "aws_secretsmanager_secret_version" "database_url" {
  count         = length(var.database_url_value) > 0 ? 1 : 0
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = var.database_url_value
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

  cpu           = 256
  memory        = 512
  desired_count = 1
  port          = 8000
  env_vars      = { AWS_REGION = var.aws_region }
  # Cloud Map registration and DB secret
  service_discovery_service_arn = aws_service_discovery_service.rag.arn
  secrets = {
    DATABASE_URL = aws_secretsmanager_secret.database_url.arn
  }
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

  cpu           = 256
  memory        = 512
  desired_count = 1
  port          = 8080
  env_vars = {
    AWS_REGION  = var.aws_region
    RAG_BASE_URL = "http://rag.${var.project}.${var.env}.local:8000"
  }
  # ALB integration
  target_group_arn     = aws_lb_target_group.gateway.arn
  ingress_source_sg_id = aws_security_group.alb.id
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

  # Minimal IAM permissions for SQS access
  inline_task_policy_json = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:SendMessage"
        ],
        Resource = [
          module.sqs.ingest_queue_arn,
          module.sqs.replan_queue_arn
        ]
      }
    ]
  })
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
  instance_class    = "db.t4g.micro"
  multi_az          = false
  allocated_storage = 20
  backup_retention  = 7
}

module "qdrant" {
  source = "./modules/qdrant"

  project               = var.project
  env                   = var.env
  cluster_name          = module.ecs.cluster_name
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = "10.0.0.0/16"
  private_subnet_ids    = module.vpc.private_subnets
  snapshots_bucket_name = module.s3.snapshots_bucket_name
  aws_region            = var.aws_region

  # Cost-saving defaults
  cpu           = 512
  memory        = 1024
  desired_count = 1
}
