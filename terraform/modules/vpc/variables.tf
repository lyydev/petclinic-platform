variable "project" {
  type        = string
  description = "Project name"
  default     = "petclinic"
}

variable "environment" {
  type        = string
  description = "Environment (dev/prod)"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "Must be a valid IPv4 CIDR block format."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs"

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "All elements must be valid IPv4 CIDR block formats."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs for subnets"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
