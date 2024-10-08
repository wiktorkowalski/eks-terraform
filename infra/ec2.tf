module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.6.1"

  name = "bastion"

  # TODO: CHANGE TO BASTION IMAGE FOR SECURITY
  ami           = "ami-0a636034c582e2138" # Ubuntu 24.04 arm64
  instance_type = "t4g.nano"
  key_name      = "WiktorPC"
  monitoring    = true

  create_spot_instance                = true
  spot_instance_interruption_behavior = "stop"
  spot_price                          = 0.70
  spot_type                           = "persistent"

  vpc_security_group_ids      = [aws_security_group.bastion.id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  instance_tags = {
    name        = "bastion"
  }
}

resource "aws_security_group" "bastion" {
  name        = "bastion-sg"
  description = "Security group for Bastion jump host"
  vpc_id      = module.vpc.vpc_id

  # Allow inbound ICMP traffic from anywhere
  ingress {
    protocol    = "icmp"
    from_port   = 8
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound SSH traffic from anywhere
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound traffic to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# resource "null_resource" "wait_for_public_dns" {
#   provisioner "local-exec" {
#     command = "while [ -z \"$(aws ec2 describe-instances --instance-id ${module.ec2_instance.id} --query 'Reservations[0].Instances[0].PublicDnsName' --output text)\" ]; do sleep 5; done"
#   }
# }

resource "aws_route53_record" "bastion" {
  depends_on = [
    # null_resource.wait_for_public_dns,
    module.ec2_instance.public_dns
  ]
  zone_id    = aws_route53_zone.aws.zone_id
  name       = "bastion.${aws_route53_zone.aws.name}"
  type       = "CNAME"
  ttl        = 300
  records    = [module.ec2_instance.public_dns]
}
