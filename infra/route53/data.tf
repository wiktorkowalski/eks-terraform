# Import locals from root module
locals {
  cluster_name = "eks-terraform"
}

# Note: NLB data source moved to infra/eks/nlb.tf
# Wildcard DNS record is now created in the EKS module to avoid dependency issues
