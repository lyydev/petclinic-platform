variable "project" {
  type        = string
  description = "Project name"
  default     = "petclinic"
}

variable "environment" {
  type        = string
  description = "Environment"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "service_names" {
  type        = list(string)
  description = "List of service names"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}

variable "image_retention_count" {
  type        = number
  description = "Number of tagged images to retain"
  default     = 10
}
