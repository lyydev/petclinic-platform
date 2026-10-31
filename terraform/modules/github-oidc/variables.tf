variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Target deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be either 'dev' or 'prod'."
  }
}

variable "github_org" {
  description = "GitHub username or organization owning the application repository fork"
  type        = string
  default     = "lyydev"

  validation {
    condition     = length(trimspace(var.github_org)) > 0 && !strcontains(var.github_org, "*")
    error_message = "github_org must be a specific GitHub username/organization and must not contain wildcards."
  }
}

variable "github_repo" {
  description = "Application repository name where the CI Docker build workflow runs"
  type        = string
  default     = "spring-petclinic-microservices"

  validation {
    condition     = var.github_repo == "spring-petclinic-microservices"
    error_message = "github_repo must be 'spring-petclinic-microservices' (OIDC trust is scoped strictly to the application repo)."
  }
}

variable "github_branch" {
  description = "Git branch allowed to assume the GitHub Actions IAM role"
  type        = string
  default     = "main"

  validation {
    condition     = length(trimspace(var.github_branch)) > 0 && !strcontains(var.github_branch, "*")
    error_message = "github_branch must be an explicit branch name without wildcards."
  }
}

variable "create_oidc_provider" {
  description = "Whether to create the account-level IAM OIDC provider for token.actions.githubusercontent.com (set false if already created in the same AWS account)"
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "Optional ARN of an existing GitHub Actions IAM OIDC provider when create_oidc_provider is false"
  type        = string
  default     = ""
}

variable "additional_thumbprints" {
  description = "Backup root CA SHA-1 thumbprints for GitHub Actions OIDC provider certificate rotation"
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs that GitHub Actions is allowed to push images to"
  type        = list(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0 && alltrue([for arn in var.ecr_repository_arns : arn != "*" && !endswith(arn, ":*")])
    error_message = "ecr_repository_arns must contain explicit ECR repository ARNs without wildcards."
  }
}

variable "role_name" {
  description = "Optional custom IAM role name override (defaults to petclinic-{env}-github-actions-role)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to merge onto all taggable IAM resources"
  type        = map(string)
  default     = {}
}
