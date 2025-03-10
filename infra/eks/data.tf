data "aws_vpc" "vpc" {
  tags = {
    Name = "${local.cluster_name}-vpc"
  }
}

data "aws_subnets" "private" {
  tags = {
    "private" = "true" # TODO: add more specific tags
  }
}

data "aws_route53_zone" "aws" {
  name = "aws.wiktorkowalski.pl" # TODO: move to variables
}
