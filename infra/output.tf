output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "bastion_address" {
  value = aws_route53_record.bastion.fqdn
}

# IRSA Role ARNs for Kubernetes service accounts
output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager service account"
  value       = module.eks.cert_manager_role_arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for external-dns service account"
  value       = module.eks.external_dns_role_arn
}
