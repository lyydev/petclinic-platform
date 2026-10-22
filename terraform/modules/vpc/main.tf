resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project}-${var.environment}-vpc"
    }
  )
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  # No ingress or egress blocks; drops all traffic to satisfy CKV2_AWS_12
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/${var.project}-${var.environment}-flow-logs"
  retention_in_days = 7
  # checkov:skip=CKV_AWS_158: KMS encryption for logs is overkill for this learning project
}

data "aws_iam_policy_document" "vpc_flow_log_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "vpc_flow_log" {
  name               = "${var.project}-${var.environment}-vpc-flow-log-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_log_assume_role.json
}

data "aws_iam_policy_document" "vpc_flow_log_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name   = "${var.project}-${var.environment}-vpc-flow-log-policy"
  role   = aws_iam_role.vpc_flow_log.id
  policy = data.aws_iam_policy_document.vpc_flow_log_policy.json
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project}-${var.environment}-igw"
    }
  )
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name                                                      = "${var.project}-${var.environment}-public-subnet-${count.index + 1}"
      "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
      "kubernetes.io/role/elb"                                  = "1"
    }
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project}-${var.environment}-public-rt"
    }
  )
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Security Groups ---

resource "aws_security_group" "eks_cluster" {
  name        = "${var.project}-${var.environment}-eks-cluster-sg"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.main.id
  # checkov:skip=CKV2_AWS_5: "Ensure that Security Groups are attached to another resource"
  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-eks-cluster-sg" })
}

resource "aws_security_group" "eks_node" {
  name        = "${var.project}-${var.environment}-eks-node-sg"
  description = "EKS node security group"
  vpc_id      = aws_vpc.main.id
  # checkov:skip=CKV2_AWS_5: "Ensure that Security Groups are attached to another resource"
  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-eks-node-sg" })
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "RDS security group"
  vpc_id      = aws_vpc.main.id
  # checkov:skip=CKV2_AWS_5: "Ensure that Security Groups are attached to another resource"
  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-rds-sg" })
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id
  # checkov:skip=CKV2_AWS_5: "Ensure that Security Groups are attached to another resource"
  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-alb-sg" })
}

# --- SG Rules: EKS Cluster ---
resource "aws_security_group_rule" "cluster_from_nodes" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_node.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  description              = "API Server access from nodes"
}

resource "aws_security_group_rule" "cluster_outbound" {
  # checkov:skip=CKV_AWS_282: "Ensure no security groups allow fully unrestricted outbound traffic" (Required for EKS)
  type              = "egress"
  security_group_id = aws_security_group.eks_cluster.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  description       = "All outbound"
}

# --- SG Rules: EKS Node ---
resource "aws_security_group_rule" "nodes_from_cluster" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.eks_cluster.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  description              = "All from cluster SG"
  # checkov:skip=CKV_AWS_274: EKS managed node groups require permissive ingress from the cluster security group for metrics, logs, and webhooks
}

resource "aws_security_group_rule" "nodes_self" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.eks_node.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  description              = "Inter-node communication"
}

resource "aws_security_group_rule" "nodes_nodeport_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.alb.id
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  description              = "NodePort services"
}

resource "aws_security_group_rule" "nodes_healthcheck_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.alb.id
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  description              = "Health checks from ALB"
}

resource "aws_security_group_rule" "nodes_outbound" {
  # checkov:skip=CKV_AWS_282: "Ensure no security groups allow fully unrestricted outbound traffic" (Required for nodes to pull images/updates)
  type              = "egress"
  security_group_id = aws_security_group.eks_node.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  description       = "All outbound"
}

# --- SG Rules: RDS ---
resource "aws_security_group_rule" "rds_from_nodes" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.eks_node.id
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  description              = "MySQL from nodes"
}

# --- SG Rules: ALB ---
resource "aws_security_group_rule" "alb_http" {
  # checkov:skip=CKV_AWS_260: "Ensure no security groups allow ingress from 0.0.0.0:0 to port 80" (ALB needs public access)
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  description       = "HTTP from internet"
}

resource "aws_security_group_rule" "alb_https" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  description       = "HTTPS from internet"
}

resource "aws_security_group_rule" "alb_to_nodes_nodeport" {
  type                     = "egress"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.eks_node.id
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  description              = "To nodes (target group)"
}

resource "aws_security_group_rule" "alb_to_nodes_healthcheck" {
  type                     = "egress"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.eks_node.id
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  description              = "Health checks to nodes"
}
