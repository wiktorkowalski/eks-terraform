output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager service account"
  value       = aws_iam_role.cert_manager.arn
}
