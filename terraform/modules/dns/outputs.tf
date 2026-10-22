output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = data.aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "Route 53 zone name servers"
  value       = data.aws_route53_zone.main.name_servers
}

output "zone_name_servers" {
  description = "Route 53 zone name servers (alias for name_servers)"
  value       = data.aws_route53_zone.main.name_servers
}

output "certificate_arn" {
  description = "Validated ACM certificate ARN"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "certificate_request_arn" {
  description = "ACM certificate request ARN before validation completes"
  value       = aws_acm_certificate.main.arn
}

output "certificate_validation_id" {
  description = "ACM certificate validation ID"
  value       = aws_acm_certificate_validation.main.id
}

output "domain_name" {
  description = "Domain name configured in Route 53 and ACM"
  value       = var.domain_name
}

output "alb_record_fqdn" {
  description = "FQDN of the Route 53 ALB alias record (if created)"
  value       = try(aws_route53_record.alb[0].fqdn, null)
}
