variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
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

variable "openai_api_key" {
  description = "OpenAI API key value for GenAI service (never hardcode)"
  type        = string
  sensitive   = true
  default     = "placeholder-openai-api-key"
}

variable "github_org" {
  description = "GitHub username or organization owning the spring-petclinic-microservices fork"
  type        = string
  default     = "lyydev"

  validation {
    condition     = length(trimspace(var.github_org)) > 0 && !strcontains(var.github_org, "*")
    error_message = "github_org must be a non-empty GitHub username/org and must not contain wildcards (*)."
  }
}

variable "github_repo" {
  description = "Application repository name trusted via GitHub OIDC"
  type        = string
  default     = "spring-petclinic-microservices"

  validation {
    condition     = length(trimspace(var.github_repo)) > 0 && !strcontains(var.github_repo, "*")
    error_message = "github_repo must be a non-empty repository name and must not contain wildcards (*)."
  }
}

variable "create_github_oidc_provider" {
  description = "Whether to create the account-level GitHub Actions IAM OIDC provider (false when already provisioned by dev in the same account)"
  type        = bool
  default     = false
}

variable "github_oidc_provider_arn" {
  description = "Optional ARN of an existing GitHub Actions IAM OIDC provider when create_github_oidc_provider = false"
  type        = string
  default     = null
}
