module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.14.0"

  cluster_name              = local.cluster_name
  cluster_version           = "1.29"
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # iam_role_additional_policies = [
  #   aws_iam_policy.route53,
  # ]

  eks_managed_node_group_defaults = {
    disk_size = 50
  }

  eks_managed_node_groups = {
    spot = {
      min_size     = 1
      desired_size = 2
      max_size     = 4

      instance_types = ["m7g.large", "m7g.xlarge"]
      capacity_type  = "SPOT"
      ami_type       = "AL2_ARM_64"
    }
  }

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true


  # https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html
  cluster_addons = {
    vpc-cni = {
      most_recent = true
      # resolve_conflicts        = "OVERWRITE"
      # before_compute = true
      # https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html
      # addon_version            = "v1.18.2-eksbuild.1"
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
    aws-mountpoint-s3-csi-driver = {
      most_recent = true
    }
    snapshot-controller = {
      most_recent = true
    }
    # adot = {
    #   most_recent = true
    # }
    # aws-guardduty-agent = {
    #   most_recent = true
    # }
    amazon-cloudwatch-observability = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }
}

resource "aws_iam_role_policy_attachment" "route53" {
  for_each = module.eks.eks_managed_node_groups

  policy_arn = aws_iam_policy.route53.arn
  role       = each.value.iam_role_name
}

# policy for route 53
data "aws_iam_policy_document" "route53" {
  statement {
    actions = ["*"]

    resources = [
      data.aws_route53_zone.zone.arn,
    ]
  }
}

resource "aws_iam_policy" "route53" {
  name        = "route53"
  description = "Allows EKS to manage Route53"
  policy      = data.aws_iam_policy_document.route53.json
}


# policy for ACM

data "aws_iam_policy_document" "acm" {
  statement {
    actions = [
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "acm:GetCertificate",
      "acm:RequestCertificate",
      "acm:DeleteCertificate",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "acm" {
  name        = "acm"
  description = "Allows EKS to manage ACM"
  policy      = data.aws_iam_policy_document.acm.json
}

resource "aws_iam_role_policy_attachment" "acm" {
  for_each = module.eks.eks_managed_node_groups

  policy_arn = aws_iam_policy.acm.arn
  role       = each.value.iam_role_name
}

resource "aws_iam_role" "eks_admin" {
  name = "eks_admin"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement : [
      {
        Effect : "Allow",
        Principal : {
          Service : "eks.amazonaws.com"
        },
        Action : "sts:AssumeRole"
      }
    ]
  })
}

data "aws_eks_cluster_auth" "cluster_auth" {
  depends_on = [module.eks.cluster_id]
  name       = module.eks.cluster_name
}

provider "kubernetes" {
  # config_path = "~/.kube/config"
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster_auth.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster_auth.token
  }
}
