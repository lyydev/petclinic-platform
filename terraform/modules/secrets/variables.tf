variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be either 'dev' or 'prod'."
  }
}

variable "openai_api_key" {
  description = "OpenAI API key value for GenAI service (never hardcode)"
  type        = string
  sensitive   = true
  default     = "placeholder-openai-api-key"
}

variable "recovery_window_in_days" {
  description = "Number of days that AWS Secrets Manager waits before deleting a secret (0 for dev, 7-30 for prod)"
  type        = number
  default     = 0
  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 (force delete) or between 7 and 30 days."
  }
}

variable "tags" {
  description = "Additional tags for secrets"
  type        = map(string)
  default     = {}
}
