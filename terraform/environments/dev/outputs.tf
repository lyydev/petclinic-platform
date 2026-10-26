output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "EKS cluster security group ID"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "EKS node security group ID"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = module.vpc.alb_sg_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL"
  value       = module.eks.oidc_provider_url
}

output "kubeconfig_update_cmd" {
  description = "Command to update local kubeconfig"
  value       = module.eks.kubeconfig_update_cmd
}

output "node_group_name" {
  description = "EKS Node Group Name"
  value       = module.eks.node_group_name
}

output "node_role_arn" {
  description = "EKS Node Role ARN"
  value       = module.eks.node_role_arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

output "rds_endpoint" {
  description = "RDS endpoint hostname"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port (3306)"
  value       = module.rds.port
}

output "rds_db_instance_id" {
  description = "RDS instance ID"
  value       = module.rds.db_instance_id
}

output "rds_db_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "rds_secret_arn" {
  description = "Secrets Manager secret ARN for RDS credentials"
  value       = module.rds.secret_arn
}

output "rds_secret_name" {
  description = "Secrets Manager secret name for RDS credentials"
  value       = module.rds.secret_name
}

output "rds_jdbc_url" {
  description = "JDBC connection URL for Spring Boot applications"
  value       = "jdbc:mysql://${module.rds.endpoint}:${module.rds.port}/${module.rds.db_name}"
}

output "lb_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM role ARN"
  value       = module.eks.lb_controller_role_arn
}

output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = module.dns.zone_id
}

output "name_servers" {
  description = "Route 53 zone name servers"
  value       = module.dns.name_servers
}

output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = module.dns.certificate_arn
}

output "alb_record_fqdn" {
  description = "FQDN of the Route 53 ALB alias record (if created)"
  value       = module.dns.alb_record_fqdn
}

output "eso_role_arn" {
  description = "External Secrets Operator IAM role ARN"
  value       = module.eks.eso_role_arn
}

output "eso_role_name" {
  description = "External Secrets Operator IAM role name"
  value       = module.eks.eso_role_name
}

output "openai_secret_arn" {
  description = "Secrets Manager ARN for OpenAI API key"
  value       = module.secrets.openai_secret_arn
}

output "openai_secret_name" {
  description = "Secrets Manager secret name for OpenAI API key"
  value       = module.secrets.openai_secret_name
}

