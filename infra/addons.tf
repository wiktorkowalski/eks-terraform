module "eks_blueprints_addons" {
  source     = "aws-ia/eks-blueprints-addons/aws"
  version    = "1.16.3" #ensure to update this to the latest/desired version
  depends_on = [module.eks.cluster_id]

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # 3rd party addons
  # kubecost_kubecost = {
  #   most_recent = true
  # }
  # grafana-labs_kubernetes-monitoring = {
  #   most_recent = true
  # }
  # newrelic_newrelic-infra = {
  #   most_recent = true
  # }

  # enable_cluster_proportional_autoscaler = true
  enable_aws_load_balancer_controller = true
  # enable_karpenter                       = true
  enable_kube_prometheus_stack          = true
  enable_metrics_server                 = true
  enable_cert_manager                   = true
  
  
  enable_external_dns                   = true
  external_dns_route53_zone_arns        = [aws_route53_zone.aws.arn]
  external_dns = {
    set = [
      {
        name = "policy"
        value = "sync"
      }
    ]
  }
  
  enable_argocd                         = true
  argocd = {
    namespace = "argocd"
    name = "argocd"
    chart_version = "7.3.10"

    values = [
<<EOF
global:
  configs:
    params:
      server.insecure: true
EOF
    ]

    set = [
        {
            name = "server.insecure"
            value = "true"
        }
    ]
  }
  
  cert_manager_route53_hosted_zone_arns = [aws_route53_zone.aws.arn]

  providers = {
    kubernetes = kubernetes
    helm = helm
  }
}
