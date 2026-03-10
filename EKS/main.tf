provider "aws" {
  region = "ap-south-2"
}

resource "aws_vpc" "blog_site_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "blog-site-vpc"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_subnet" "blog_site_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.blog_site_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.blog_site_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["ap-south-2a", "ap-south-2b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                                      = "blog-site-subnet-${count.index}"
    Project                                   = "blog-site"
    Environment                               = "production"
    ManagedBy                                 = "terraform"
    "kubernetes.io/role/elb"                  = "1"
    "kubernetes.io/cluster/blog-site-cluster" = "shared"
  }
}

resource "aws_internet_gateway" "blog_site_igw" {
  vpc_id = aws_vpc.blog_site_vpc.id

  tags = {
    Name        = "blog-site-igw"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table" "blog_site_route_table" {
  vpc_id = aws_vpc.blog_site_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.blog_site_igw.id
  }

  tags = {
    Name        = "blog-site-route-table"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table_association" "blog_site_association" {
  count          = 2
  subnet_id      = aws_subnet.blog_site_subnet[count.index].id
  route_table_id = aws_route_table.blog_site_route_table.id
}

resource "aws_security_group" "blog_site_cluster_sg" {
  vpc_id = aws_vpc.blog_site_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "blog-site-cluster-sg"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "blog_site_node_sg" {
  vpc_id = aws_vpc.blog_site_vpc.id

  # Allow traffic from within VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.blog_site_vpc.cidr_block]
    description = "Allow all traffic from within VPC"
  }

  # Allow NodePort range for LoadBalancer services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow NodePort range for Kubernetes services"
  }

  # Allow HTTPS from anywhere (for ALB health checks and traffic)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic"
  }

  # Allow HTTP from anywhere (for ALB health checks and traffic)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "blog-site-node-sg"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_eks_cluster" "blog_site" {
  name     = "blog-site-cluster"
  role_arn = aws_iam_role.blog_site_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.blog_site_subnet[*].id
    security_group_ids = [aws_security_group.blog_site_cluster_sg.id]
  }

  tags = {
    Name        = "blog-site-cluster"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}


# EBS CSI Driver - Install manually after cluster creation
# Requires OIDC provider and IAM role
# See COMPLETE-DEPLOYMENT-GUIDE.md Step 2

# resource "aws_eks_addon" "ebs_csi_driver" {
#   cluster_name = aws_eks_cluster.blog_site.name
#   addon_name   = "aws-ebs-csi-driver"
# 
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
# 
#   depends_on = [
#     aws_eks_cluster.blog_site,
#     aws_eks_node_group.blog_site
#   ]
# 
#   tags = {
#     Name        = "blog-site-ebs-csi-driver"
#     Project     = "blog-site"
#     Environment = "production"
#     ManagedBy   = "terraform"
#   }
# }


resource "aws_eks_node_group" "blog_site" {
  cluster_name    = aws_eks_cluster.blog_site.name
  node_group_name = "blog-site-node-group"
  node_role_arn   = aws_iam_role.blog_site_node_group_role.arn
  subnet_ids      = aws_subnet.blog_site_subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  instance_types = ["t3.medium"]

  remote_access {
    ec2_ssh_key               = var.ssh_key_name
    source_security_group_ids = [aws_security_group.blog_site_node_sg.id]
  }

  tags = {
    Name        = "blog-site-node-group"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "blog_site_cluster_role" {
  name = "blog-site-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Name        = "blog-site-cluster-role"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "blog_site_cluster_role_policy" {
  role       = aws_iam_role.blog_site_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "blog_site_node_group_role" {
  name = "blog-site-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Name        = "blog-site-node-group-role"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "blog_site_node_group_role_policy" {
  role       = aws_iam_role.blog_site_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "blog_site_node_group_cni_policy" {
  role       = aws_iam_role.blog_site_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "blog_site_node_group_registry_policy" {
  role       = aws_iam_role.blog_site_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "blog_site_node_group_ebs_policy" {
  role       = aws_iam_role.blog_site_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
