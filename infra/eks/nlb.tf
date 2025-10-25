# Network Load Balancer for Traefik ingress
# This NLB will route traffic to Traefik DaemonSet running on NodePort

resource "aws_lb" "traefik" {
  name               = "${local.cluster_name}-traefik-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${local.cluster_name}-traefik-nlb"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Target group for HTTP traffic (NodePort 30080)
resource "aws_lb_target_group" "http" {
  name     = "${local.cluster_name}-traefik-http"
  port     = 30080
  protocol = "TCP"
  vpc_id   = data.aws_vpc.vpc.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/ping"
    port                = "30080"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
  }

  deregistration_delay = 30

  tags = {
    Name        = "${local.cluster_name}-traefik-http"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Target group for HTTPS traffic (NodePort 30443)
resource "aws_lb_target_group" "https" {
  name     = "${local.cluster_name}-traefik-https"
  port     = 30443
  protocol = "TCP"
  vpc_id   = data.aws_vpc.vpc.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/ping"
    port                = "30080"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
  }

  deregistration_delay = 30

  tags = {
    Name        = "${local.cluster_name}-traefik-https"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# NLB listener for HTTP (port 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.traefik.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

# NLB listener for HTTPS (port 443)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.traefik.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

# Auto-register bootstrap node instances to target groups
# This ensures the NLB can route traffic immediately after cluster creation
resource "aws_autoscaling_attachment" "bootstrap_http" {
  for_each = module.eks.eks_managed_node_groups

  autoscaling_group_name = each.value.node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.http.arn
}

resource "aws_autoscaling_attachment" "bootstrap_https" {
  for_each = module.eks.eks_managed_node_groups

  autoscaling_group_name = each.value.node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.https.arn
}

# Wildcard DNS record pointing to NLB
# Created here instead of route53 module to avoid dependency issues
resource "aws_route53_record" "wildcard" {
  zone_id = data.aws_route53_zone.aws.zone_id
  name    = "*.${data.aws_route53_zone.aws.name}"
  type    = "A"

  alias {
    name                   = aws_lb.traefik.dns_name
    zone_id                = aws_lb.traefik.zone_id
    evaluate_target_health = true
  }
}

# Output NLB DNS name for reference
output "nlb_dns_name" {
  description = "DNS name of the NLB for Traefik ingress"
  value       = aws_lb.traefik.dns_name
}

output "nlb_zone_id" {
  description = "Zone ID of the NLB for Route53 alias record"
  value       = aws_lb.traefik.zone_id
}

output "wildcard_dns" {
  description = "Wildcard DNS record for cluster services"
  value       = aws_route53_record.wildcard.fqdn
}
