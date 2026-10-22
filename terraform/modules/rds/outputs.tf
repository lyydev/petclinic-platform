output "endpoint" {
  description = "RDS endpoint hostname"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS port (3306)"
  value       = aws_db_instance.main.port
}

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "secret_arn" {
  description = "Secrets Manager secret ARN for RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.arn
}

output "secret_name" {
  description = "Secrets Manager secret name for RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.name
}
