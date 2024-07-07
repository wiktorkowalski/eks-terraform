output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "bastion_address" {
  value = aws_route53_record.bastion.fqdn
}
