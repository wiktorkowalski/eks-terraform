output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "bastion_public_ip" {
  value = module.ec2_instance.public_ip
}
