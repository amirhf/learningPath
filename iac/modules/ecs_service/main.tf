resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.project}-${var.env}-${var.service_name}"
  retention_in_days = 14
}

resource "aws_iam_role" "exec" {
  name = "${var.project}-${var.env}-${var.service_name}-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "exec_attach" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow execution role to read specific secrets when provided
resource "aws_iam_policy" "secrets_read" {
  count  = length(local.secret_arns) > 0 ? 1 : 0
  name   = "${var.project}-${var.env}-${var.service_name}-secrets-read"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = local.secret_arns
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "exec_attach_secrets" {
  count      = length(local.secret_arns) > 0 ? 1 : 0
  role       = aws_iam_role.exec.name
  policy_arn = aws_iam_policy.secrets_read[0].arn
}

resource "aws_iam_role" "task" {
  name = "${var.project}-${var.env}-${var.service_name}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

locals {
  env_list = [for k, v in var.env_vars : { name = k, value = v }]
  port_mappings = var.port > 0 ? [{ containerPort = var.port, hostPort = var.port, protocol = "tcp" }] : []
  secrets_list = [for k, v in var.secrets : { name = k, valueFrom = v }]
  secret_arns = [for v in values(var.secrets) : v]
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.project}-${var.env}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name         = var.container_name
      image        = var.image
      essential    = true
      portMappings = local.port_mappings
      environment  = local.env_list
      secrets      = local.secrets_list
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# Optional inline policy for task role
resource "aws_iam_role_policy" "task_inline" {
  count  = var.inline_task_policy_json != "" ? 1 : 0
  name   = "${var.project}-${var.env}-${var.service_name}-inline"
  role   = aws_iam_role.task.id
  policy = var.inline_task_policy_json
}

resource "aws_security_group" "this" {
  name        = "${var.project}-${var.env}-${var.service_name}-sg"
  description = "SG for ${var.service_name}"
  vpc_id      = var.vpc_id

  # Ingress from ALB SG if provided, otherwise from VPC CIDR
  dynamic "ingress" {
    for_each = (var.port > 0 && var.ingress_source_sg_id != "") ? [1] : []
    content {
      from_port       = var.port
      to_port         = var.port
      protocol        = "tcp"
      security_groups = [var.ingress_source_sg_id]
    }
  }

  dynamic "ingress" {
    for_each = (var.port > 0 && var.ingress_source_sg_id == "") ? [1] : []
    content {
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "this" {
  name            = "${var.project}-${var.env}-${var.service_name}"
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  enable_execute_command = true

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [aws_security_group.this.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = (var.target_group_arn != "" && var.port > 0) ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.port
    }
  }

  dynamic "service_registries" {
    for_each = var.service_discovery_service_arn != "" ? [1] : []
    content {
      registry_arn   = var.service_discovery_service_arn
      container_name = var.container_name
    }
  }
}
