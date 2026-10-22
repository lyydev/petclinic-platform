variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for DB subnet group"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS security group ID"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Max autoscale storage in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention in days"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on delete"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Deletion protection"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Specifies whether any database modifications are applied immediately, or during the next maintenance window"
  type        = bool
  default     = false
}

variable "recovery_window_in_days" {
  description = "Number of days that AWS Secrets Manager waits before deleting secret (0 to force immediate deletion)"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
