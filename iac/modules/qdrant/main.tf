resource "aws_security_group" "qdrant_svc" {
  name        = "${var.project}-${var.env}-qdrant-svc-sg"
  description = "Qdrant ECS service SG"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 6333
    to_port     = 6333
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_subnet" "selected" {
  id = var.private_subnet_ids[0]
}

resource "aws_iam_role" "exec" {
  name = "${var.project}-${var.env}-qdrant-exec"
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
  name = "${var.project}-${var.env}-qdrant-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_security_group" "qdrant_efs" {
  name        = "${var.project}-${var.env}-qdrant-efs-sg"
  description = "EFS SG for Qdrant"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.qdrant_svc.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "this" {
  creation_token = "${var.project}-${var.env}-qdrant-efs"
  encrypted      = true
  throughput_mode = "bursting"
  availability_zone_name = data.aws_subnet.selected.availability_zone
  tags = {
    Project = var.project
    Env     = var.env
  }
}

resource "aws_efs_mount_target" "this" {
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.private_subnet_ids[0]
  security_groups = [aws_security_group.qdrant_efs.id]
}

resource "aws_ecs_task_definition" "qdrant" {
  family                   = "${var.project}-${var.env}-qdrant"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn

  volume {
    name = "qdrant-data"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.this.id
      transit_encryption = "ENABLED"
      root_directory = "/"
    }
  }

  container_definitions = jsonencode([
    {
      name  = "qdrant"
      image = "qdrant/qdrant:latest"
      essential = true
      portMappings = [{ containerPort = 6333, hostPort = 6333, protocol = "tcp" }]
      mountPoints = [{ sourceVolume = "qdrant-data", containerPath = "/qdrant/storage" }]
      environment = [
        { name = "QDRANT__STORAGE__STORAGE_PATH", value = "/qdrant/storage" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = var.aws_region
          awslogs-group         = aws_cloudwatch_log_group.qdrant.name
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_cloudwatch_log_group" "qdrant" {
  name              = "/ecs/${var.project}-${var.env}-qdrant"
  retention_in_days = 14
}

# Cloud Map service discovery for Qdrant
resource "aws_service_discovery_service" "this" {
  name = var.service_discovery_service_name

  dns_config {
    namespace_id  = var.service_discovery_namespace_id
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

resource "aws_ecs_service" "qdrant" {
  name            = "${var.project}-${var.env}-qdrant"
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.qdrant.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets         = [var.private_subnet_ids[0]]
    security_groups = [aws_security_group.qdrant_svc.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this.arn
  }
}

