output "openai_secret_arn" {
  description = "Secrets Manager ARN for OpenAI API key"
  value       = aws_secretsmanager_secret.openai_api_key.arn
}

output "openai_secret_name" {
  description = "Secrets Manager secret name for OpenAI API key"
  value       = aws_secretsmanager_secret.openai_api_key.name
}
