locals {
  oidc_url      = "https://token.actions.githubusercontent.com"
  role_name     = var.role_name != "" ? var.role_name : "${var.project}-${var.environment}-github-actions-role"
  policy_name   = "${var.project}-${var.environment}-github-actions-ecr-push"
  subject_claim = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"

  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = "cicd"
  })
}

# Fetch current TLS certificate chain for GitHub Actions OIDC endpoint
data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = local.oidc_url
}

# Account-level IAM OIDC identity provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = local.oidc_url
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = distinct(concat(
    [data.tls_certificate.github[0].certificates[0].sha1_fingerprint],
    var.additional_thumbprints
  ))

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-github-oidc"
  })
}

data "aws_iam_openid_connect_provider" "github" {
  count = !var.create_oidc_provider && var.oidc_provider_arn == "" ? 1 : 0
  url   = local.oidc_url
}

locals {
  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : (var.oidc_provider_arn != "" ? var.oidc_provider_arn : data.aws_iam_openid_connect_provider.github[0].arn)
  )
}

# OIDC federation trust policy restricted strictly to:
#   aud = sts.amazonaws.com
#   sub = repo:lyydev/spring-petclinic-microservices:ref:refs/heads/main
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "GitHubActionsOIDCTrust"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.subject_claim]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = local.role_name
  description          = "OIDC federated IAM role for GitHub Actions ECR image push from ${var.github_org}/${var.github_repo}"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = local.role_name
  })
}

# Least-privilege ECR-only push policy (no ecr:*, no *, no non-ECR services)
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRGetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_policy" "ecr_push" {
  # checkov:skip=CKV_AWS_355: AWS IAM requires Resource * for ecr:GetAuthorizationToken account-level token API
  name        = local.policy_name
  description = "Least-privilege ECR image push policy for GitHub Actions in ${var.project}-${var.environment}"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = merge(local.common_tags, {
    Name = local.policy_name
  })
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
