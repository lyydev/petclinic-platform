variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "The domain name for the Route 53 hosted zone and ACM certificate"
  type        = string
}

variable "record_name" {
  description = "Subdomain or record name for the Route 53 ALB alias (e.g. petclinic-dev.example.com)"
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "DNS name of the ALB created by the AWS Load Balancer Controller (e.g. *.elb.amazonaws.com)"
  type        = string
  default     = ""

  validation {
    condition     = var.alb_dns_name == "" || can(regex("elb\\..*\\.amazonaws\\.com", var.alb_dns_name)) || can(regex("elb\\.amazonaws\\.com", var.alb_dns_name))
    error_message = "alb_dns_name must be an AWS ELB DNS name (ending in .elb.amazonaws.com) or left empty if the ALB is not yet created."
  }
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the ALB (defaults to us-east-1 ALB hosted zone ID Z35SXDOTRQ7X7K)"
  type        = string
  default     = "Z35SXDOTRQ7X7K"
}

variable "evaluate_target_health" {
  description = "Whether to evaluate target health for the Route 53 alias record"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
