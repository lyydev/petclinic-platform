data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source              = "../../modules/vpc"
  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "eks" {
  source = "../../modules/eks"

  project             = var.project
  environment         = var.environment
  cluster_version     = var.cluster_version
  subnet_ids          = module.vpc.public_subnet_ids
  cluster_sg_id       = module.vpc.eks_cluster_sg_id
  node_sg_id          = module.vpc.eks_node_sg_id
  node_instance_types = var.node_instance_types
  node_ami_type       = var.node_ami_type
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
  node_disk_size      = var.node_disk_size
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment
  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server"
  ]
}

module "rds" {
  source = "../../modules/rds"

  project                 = var.project
  environment             = var.environment
  subnet_ids              = module.vpc.public_subnet_ids
  security_group_id       = module.vpc.rds_sg_id
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  max_allocated_storage   = 20
  multi_az                = false
  backup_retention_period = 30
  skip_final_snapshot     = false
  deletion_protection     = true
  apply_immediately       = false
  recovery_window_in_days = 7
}

module "secrets" {
  source = "../../modules/secrets"

  project                 = var.project
  environment             = var.environment
  openai_api_key          = var.openai_api_key
  recovery_window_in_days = 7
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  project              = var.project
  environment          = var.environment
  github_org           = var.github_org
  github_repo          = var.github_repo
  github_branch        = "main"
  create_oidc_provider = var.create_github_oidc_provider
  oidc_provider_arn    = var.github_oidc_provider_arn
  ecr_repository_arns  = values(module.ecr.repository_arns)
}
