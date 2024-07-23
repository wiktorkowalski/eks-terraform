data "aws_route53_zone" "wiktorkowalski" {
  name = "wiktorkowalski.pl"
}

resource "aws_route53_zone" "aws" {
  name = "aws.wiktorkowalski.pl"
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "ns" {
  zone_id = data.aws_route53_zone.wiktorkowalski.zone_id
  name    = aws_route53_zone.aws.name
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.aws.name_servers
}
