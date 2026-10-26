output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Cluster Security Group ID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL"
  value       = aws_iam_openid_connect_provider.eks.url
}

output "node_group_name" {
  description = "Managed node group name"
  value       = aws_eks_node_group.main.node_group_name
}

output "node_role_arn" {
  description = "Node IAM role ARN"
  value       = aws_iam_role.node.arn
}

output "kubeconfig_update_cmd" {
  description = "Command to update local kubeconfig"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${data.aws_region.current.name}"
}

output "lb_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM role ARN"
  value       = aws_iam_role.lb_controller.arn
}

output "lb_controller_role_name" {
  description = "AWS Load Balancer Controller IAM role name"
  value       = aws_iam_role.lb_controller.name
}

output "lb_controller_policy_arn" {
  description = "AWS Load Balancer Controller IAM policy ARN"
  value       = aws_iam_policy.lb_controller.arn
}

output "eso_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = aws_iam_role.eso.arn
}

output "eso_role_name" {
  description = "IAM role name for External Secrets Operator"
  value       = aws_iam_role.eso.name
}

output "eso_policy_arn" {
  description = "IAM policy ARN for External Secrets Operator"
  value       = aws_iam_policy.eso.arn
}
