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
variable "cluster_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.35"
  validation {
    condition     = can(regex("^1\\.(3[5-9]|[4-9][0-9])$", var.cluster_version))
    error_message = "Cluster version must be 1.35 or higher."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for cluster"
}
variable "cluster_sg_id" {
  type        = string
  description = "Cluster security group ID"
}
variable "node_sg_id" {
  type        = string
  description = "Node security group ID"
}
variable "node_instance_types" {
  type        = list(string)
  description = "Instance types for nodes"
  default     = ["t4g.small"]
}
variable "node_ami_type" {
  type        = string
  description = "AMI type for nodes"
  default     = "AL2023_ARM_64_STANDARD"
}
variable "node_min_size" {
  type        = number
  description = "Min node count"
  default     = 2
  validation {
    condition     = var.node_min_size >= 0
    error_message = "Min size must be non-negative."
  }
}
variable "node_max_size" {
  type        = number
  description = "Max node count"
  default     = 4
  validation {
    condition     = var.node_max_size >= 1
    error_message = "Max size must be at least 1."
  }
}
variable "node_desired_size" {
  type        = number
  description = "Desired node count"
  default     = 2
}
variable "node_disk_size" {
  type        = number
  description = "Disk size in GB"
  default     = 20
  validation {
    condition     = var.node_disk_size >= 20
    error_message = "Disk size must be at least 20 GB."
  }
}
variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
