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


# OIDC Identity Provider for EKS
data "tls_certificate" "blog_site_oidc" {
  url = aws_eks_cluster.blog_site.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "blog_site_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.blog_site_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.blog_site.identity[0].oidc[0].issuer

  tags = {
    Name        = "blog-site-oidc-provider"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# AWS Load Balancer Controller IAM Role
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "AmazonEKSLoadBalancerControllerRole-blog-site"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.blog_site_oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.blog_site_oidc.url, "https://", "")}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(aws_iam_openid_connect_provider.blog_site_oidc.url, "https://", "")}:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "aws-load-balancer-controller-role"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# AWS Load Balancer Controller IAM Policy
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy-blog-site"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:DescribeProtection",
          "shield:GetSubscriptionState",
          "shield:DescribeSubscription",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "CreateSecurityGroup"
          }
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = [
              "CreateTargetGroup",
              "CreateLoadBalancer"
            ]
          }
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      }
    ]
  })

  tags = {
    Name        = "aws-load-balancer-controller-policy"
    Project     = "blog-site"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
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
