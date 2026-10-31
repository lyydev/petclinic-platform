output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions IAM OIDC provider"
  value       = local.oidc_provider_arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC (set as AWS_ROLE_ARN secret)"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role assumed by GitHub Actions via OIDC"
  value       = aws_iam_role.github_actions.name
}

output "ecr_push_policy_arn" {
  description = "ARN of the least-privilege ECR push IAM policy attached to the GitHub Actions role"
  value       = aws_iam_policy.ecr_push.arn
}

output "oidc_subject_claim" {
  description = "Exact OIDC subject claim trusted by the GitHub Actions IAM role"
  value       = local.subject_claim
}
