variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "EKS node instance types"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "EKS node AMI type"
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_min_size" {
  description = "Min node count"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Max node count"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired node count"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Node disk size in GB"
  type        = number
  default     = 20
}

variable "domain_name" {
  description = "Domain name for Route 53 hosted zone and ACM certificate"
  type        = string
  default     = "k8s.lyaistorm.win"
}

variable "alb_dns_name" {
  description = "ALB DNS name for Route 53 alias record (optional; leave empty until ALB is provisioned by Kubernetes)"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "ALB hosted zone ID for Route 53 alias record (optional)"
  type        = string
  default     = "Z35SXDOTRQ7X7K"
}
