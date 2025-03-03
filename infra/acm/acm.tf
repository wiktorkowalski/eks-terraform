module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "5.0.1"

  domain_name  = aws_route53_zone.aws.name
  zone_id      = aws_route53_zone.aws.zone_id

  validation_method = "DNS"

  subject_alternative_names = [
    "*.${aws_route53_zone.aws.name}",
  ]
 
  wait_for_validation = true

  tags = {
    Name = aws_route53_zone.aws.name
  }
}