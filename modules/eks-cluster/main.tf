resource "aws_kms_key" "eks_cluster_secrets" {
  description              = "KMS key for EKS cluster ${var.cluster_name} secrets encryption"
  deletion_window_in_days  = 7
  enable_key_rotation      = true
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
}

resource "aws_kms_alias" "eks_cluster_secrets" {
  name          = "alias/${var.cluster_name}-eks-cluster-secrets-abc"
  target_key_id = aws_kms_key.eks_cluster_secrets.key_id
}

resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

resource "aws_security_group" "node" {
  name_prefix = "${var.cluster_name}-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # Allow nodes to communicate with each other
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow nodes to receive traffic from cluster control plane
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-node-sg"
  }
}

# Allow cluster to communicate with nodes
resource "aws_security_group_rule" "cluster_to_node" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.34"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Use custom security groups
  create_cluster_security_group = false
  cluster_security_group_id     = aws_security_group.cluster.id

  create_node_security_group = false
  node_security_group_id     = aws_security_group.node.id

  # Enable secrets encryption with KMS
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks_cluster_secrets.arn
    resources        = ["secrets"]
  }

  # Use a minimal node group for cost optimization
  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = ["t3a.medium"] # 2 vCPU, 4GB RAM

    disk_size = 20
    disk_type = "gp3"

    attach_cluster_primary_security_group = true
  }

  eks_managed_node_groups = {
    main = {
      name = "${var.cluster_name}-node-group"

      min_size     = var.min_nodes
      max_size     = var.max_nodes
      desired_size = var.desired_nodes

      instance_types = ["t3a.medium"]
      capacity_type  = "ON_DEMAND"

      labels = {
        Environment = var.environment
        Managed     = "terraform"
      }
    }
  }

  # CI/CD runs kubectl commands to deploy applications
  cluster_endpoint_public_access = true
  # access within VPC
  cluster_endpoint_private_access = true

  # Disable automatic access entry creation
  enable_cluster_creator_admin_permissions = false
  
  # Don't let the module create access entries automatically
  authentication_mode = "API_AND_CONFIG_MAP"
}

# Manually create access entry for GitHub Actions role
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_iam_role.github_actions.arn
  type          = "STANDARD"

  depends_on = [module.eks]
}
resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}
