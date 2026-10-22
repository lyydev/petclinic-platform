output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "VPC ARN"
  value       = aws_vpc.main.arn
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "Public subnet ARNs"
  value       = aws_subnet.public[*].arn
}

output "eks_cluster_sg_id" {
  description = "EKS cluster security group ID"
  value       = aws_security_group.eks_cluster.id
}

output "eks_cluster_sg_arn" {
  description = "EKS cluster security group ARN"
  value       = aws_security_group.eks_cluster.arn
}

output "eks_node_sg_id" {
  description = "EKS node security group ID"
  value       = aws_security_group.eks_node.id
}

output "eks_node_sg_arn" {
  description = "EKS node security group ARN"
  value       = aws_security_group.eks_node.arn
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "rds_sg_arn" {
  description = "RDS security group ARN"
  value       = aws_security_group.rds.arn
}

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "alb_sg_arn" {
  description = "ALB security group ARN"
  value       = aws_security_group.alb.arn
}
