# =====================================================
# IRSA (IAM Roles for Service Accounts)
# =====================================================
# This file defines IAM roles that Kubernetes pods can assume
# using IRSA to access AWS services securely

# Get OIDC provider information from EKS cluster
data "aws_iam_openid_connect_provider" "eks" {
  url = module.eks.cluster_oidc_issuer_url
}

locals {
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

# =====================================================
# cert-manager IAM Role
# =====================================================
# Allows cert-manager to perform DNS-01 challenges for Let's Encrypt
# by creating TXT records in Route53

data "aws_iam_policy_document" "cert_manager_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cert_manager_route53" {
  statement {
    sid    = "Route53GetChange"
    effect = "Allow"
    actions = [
      "route53:GetChange"
    ]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid    = "Route53ListHostedZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Route53ChangeRecordSets"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = [
      data.aws_route53_zone.aws.arn
    ]
  }
}

resource "aws_iam_role" "cert_manager" {
  name               = "${local.cluster_name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume_role.json

  tags = {
    Name        = "${local.cluster_name}-cert-manager"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_policy" "cert_manager" {
  name        = "${local.cluster_name}-cert-manager-route53"
  description = "Allows cert-manager to manage Route53 records for DNS-01 challenges"
  policy      = data.aws_iam_policy_document.cert_manager_route53.json

  tags = {
    Name        = "${local.cluster_name}-cert-manager-route53"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  role       = aws_iam_role.cert_manager.name
  policy_arn = aws_iam_policy.cert_manager.arn
}

# =====================================================
# external-dns IAM Role
# =====================================================
# Allows external-dns to automatically create DNS records
# in Route53 for Kubernetes services and ingresses

data "aws_iam_policy_document" "external_dns_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "external_dns_route53" {
  statement {
    sid    = "Route53ListHostedZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Route53ChangeRecordSets"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      data.aws_route53_zone.aws.arn
    ]
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${local.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role.json

  tags = {
    Name        = "${local.cluster_name}-external-dns"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "${local.cluster_name}-external-dns-route53"
  description = "Allows external-dns to manage Route53 records"
  policy      = data.aws_iam_policy_document.external_dns_route53.json

  tags = {
    Name        = "${local.cluster_name}-external-dns-route53"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}
