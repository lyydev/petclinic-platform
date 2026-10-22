# Random password for RDS master credentials
resource "random_password" "master_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# AWS Secrets Manager Secret for RDS credentials
resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "${var.project}/${var.environment}/rds-credentials"
  description             = "RDS MySQL master credentials for ${var.project}-${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.tags,
    {
      Name        = "${var.project}-${var.environment}-rds-credentials"
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project
    }
  )
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = "petclinic"
    password = random_password.master_password.result
  })
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.project}-${var.environment}-db-subnet-group-"
  description = "Database subnet group for ${var.project}-${var.environment}"
  subnet_ids  = var.subnet_ids

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project}-${var.environment}-db-subnet-group"
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project
    }
  )
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.project}-${var.environment}-mysql8-params-"
  family      = "mysql8.4"
  description = "Custom MySQL 8.4 parameter group for ${var.project}-${var.environment}"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project}-${var.environment}-mysql8-params"
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project
    }
  )
}

# RDS MySQL Instance
# checkov:skip=CKV_AWS_118: "Enhanced monitoring disabled to fit within AWS Free Tier / student budget"
# checkov:skip=CKV_AWS_129: "Log export disabled to minimize CloudWatch log storage charges"
# checkov:skip=CKV_AWS_133: "Backup retention period is configured per environment (7d dev / 30d prod per technical-spec)"
# checkov:skip=CKV_AWS_157: "Multi-AZ is disabled per ADR-0006 for cost optimization in learning project"
# checkov:skip=CKV_AWS_161: "IAM database authentication not used; application uses Secrets Manager credentials"
# checkov:skip=CKV_AWS_354: "Performance Insights disabled for db.t4g.micro to avoid performance overhead & extra cost"
# checkov:skip=CKV2_AWS_30: "Query logging not required for learning environment"
resource "aws_db_instance" "main" {
  identifier = "${var.project}-${var.environment}-mysql"

  engine         = "mysql"
  engine_version = "8.4"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = "petclinic"
  username = "petclinic"
  password = random_password.master_password.result
  port     = 3306

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false

  backup_retention_period    = var.backup_retention_period
  backup_window              = "03:00-04:00"
  maintenance_window         = "Sun:04:30-Sun:05:30"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  apply_immediately          = var.apply_immediately

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project}-${var.environment}-mysql-final-snapshot"
  deletion_protection       = var.deletion_protection

  tags = merge(
    var.tags,
    {
      Name        = "${var.project}-${var.environment}-mysql"
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project
    }
  )
}
