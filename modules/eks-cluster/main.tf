resource "aws_security_group" "cluster" {
  name_prefix = "${var.vpc_cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.vpc_cluster_name}-cluster-sg"
  }
}

resource "aws_security_group" "node" {
  name_prefix = "${var.vpc_cluster_name}-node-sg"
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

  # Allow cluster to communicate with nodes
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.vpc_cluster_name}-node-sg"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.vpc_cluster_name
  cluster_version = "1.34"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Use custom security groups
  create_cluster_security_group = false
  cluster_security_group_id     = aws_security_group.cluster.id

  create_node_security_group = false
  node_security_group_id     = aws_security_group.node.id

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
      name = "${var.vpc_cluster_name}-node-group"

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

  # Whoever creates an EKS cluster automatically gets admin access to it
  enable_cluster_creator_admin_permissions = true
  
  # Don't let the module create access entries automatically
  authentication_mode = "API_AND_CONFIG_MAP"

  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }
}

# Create access entry for your root AWS account
resource "aws_eks_access_entry" "personal_access" {
  cluster_name  = var.vpc_cluster_name
  principal_arn = var.root_account_arn
  type          = "STANDARD"

  depends_on    = [module.eks]
}
resource "aws_eks_access_policy_association" "personal_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.root_account_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on    = [aws_eks_access_entry.personal_access]
}