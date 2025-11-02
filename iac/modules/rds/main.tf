resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.env}-rds-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.env}-rds-sg"
  description = "RDS Postgres SG"
  vpc_id      = var.vpc_id
}

resource "aws_db_instance" "this" {
  identifier              = "${var.project}-${var.env}-pg"
  engine                  = "postgres"
  engine_version          = var.engine_version != "" ? var.engine_version : null
  instance_class          = var.instance_class
  db_name                 = var.db_name
  allocated_storage       = var.allocated_storage
  storage_type            = "gp3"
  username                = "postgres"
  manage_master_user_password = true

  multi_az                = var.multi_az
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.rds.id]

  backup_retention_period = var.backup_retention
  skip_final_snapshot     = true

  publicly_accessible     = false
  deletion_protection     = false
}

output "rds_endpoint" {
  value = aws_db_instance.this.address
}

