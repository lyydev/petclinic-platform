# Secrets Manager module for non-RDS application secrets
# RDS master credentials are created by the RDS module (PETPLAT-23)

# OpenAI API Key Secret
resource "aws_secretsmanager_secret" "openai_api_key" {
  # checkov:skip=CKV_AWS_149: Default AWS KMS key aws/secretsmanager used to minimize cost in learning environment
  # checkov:skip=CKV2_AWS_57: Secrets rotation is manual or managed by RDS for educational environment
  name                    = "${var.project}/${var.environment}/openai-api-key"
  description             = "OpenAI API key for ${var.project}-${var.environment} GenAI service"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.tags,
    {
      Name        = "${var.project}-${var.environment}-openai-api-key"
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project
    }
  )
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key != "" ? var.openai_api_key : "placeholder-openai-api-key"
}
