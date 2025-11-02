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

resource "aws_security_group" "this" {
  name        = "${var.project}-${var.env}-${var.service_name}-sg"
  description = "SG for ${var.service_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.port > 0 ? [1] : []
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
}
