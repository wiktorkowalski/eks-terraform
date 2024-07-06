# resource "aws_acm_certificate" "cert" {
#   domain_name       = "aws.wiktorkowalski.pl"
#   validation_method = "DNS"

#   subject_alternative_names = [
#     "grafana.aws.wiktorkowalski.pl",
#     "prometheus.aws.wiktorkowalski.pl",
#   ]

#   tags = {
#     Name = "example-cert"
#   }
# }

# resource "aws_route53_record" "cert_validation" {
#   for_each = {
#     for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       type   = dvo.resource_record_type
#       record = dvo.resource_record_value
#     }
#   }

#   zone_id = data.aws_route53_zone.zone.id
#   name    = each.value.name
#   type    = each.value.type
#   ttl     = 60
#   records = [each.value.record]
# }

# resource "aws_acm_certificate_validation" "cert_validation" {
#   certificate_arn         = aws_acm_certificate.cert.arn
#   validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
# }


# resource "aws_lb_target_group" "grafana_tg" {
#   name     = "grafana-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = module.vpc.vpc_id
# }

# resource "aws_lb_target_group" "prometheus_tg" {
#   name     = "prometheus-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = module.vpc.vpc_id
# }

# resource "aws_lb_listener" "https_listener" {
#   load_balancer_arn = aws_alb.eks.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08"
#   certificate_arn   = aws_acm_certificate.cert.arn

#   default_action {
#     type = "fixed-response"
#     fixed_response {
#       content_type = "text/plain"
#       message_body = "404: Not Found"
#       status_code  = "404"
#     }
#   }
# }

# resource "kubernetes_manifest" "grafana_ingress" {
#   manifest = {
#     apiVersion = "networking.k8s.io/v1"
#     kind       = "Ingress"
#     metadata = {
#       name      = "grafana-ingress"
#       namespace = "kube-prometheus-stack"
#       annotations = {
#         "alb.ingress.kubernetes.io/scheme"                  = "internet-facing"
#         "alb.ingress.kubernetes.io/listen-ports"            = "[{\"HTTPS\":443}]"
#         "alb.ingress.kubernetes.io/certificate-arn"         = aws_acm_certificate.cert.arn
#         "alb.ingress.kubernetes.io/target-type"             = "ip"
#         "alb.ingress.kubernetes.io/group.name"              = "monitoring-ingress-group"
#       }
#     }
#     spec = {
#       rules = [
#         {
#           host = "grafana.aws.wiktorowalski.pl"
#           http = {
#             paths = [
#               {
#                 path = "/"
#                 pathType = "Prefix"
#                 backend = {
#                   service = {
#                     name = "kube-prometheus-stack-grafana"
#                     port = {
#                       number = 80
#                     }
#                   }
#                 }
#               }
#             ]
#           }
#         }
#       ]
#     }
#   }
# }

# resource "kubernetes_manifest" "prometheus_ingress" {
#   manifest = {
#     apiVersion = "networking.k8s.io/v1"
#     kind       = "Ingress"
#     metadata = {
#       name      = "prometheus-ingress"
#       namespace = "kube-prometheus-stack"
#       annotations = {
#         "alb.ingress.kubernetes.io/scheme"                  = "internet-facing"
#         "alb.ingress.kubernetes.io/listen-ports"            = "[{\"HTTPS\":443}]"
#         "alb.ingress.kubernetes.io/certificate-arn"         = aws_acm_certificate.cert.arn
#         "alb.ingress.kubernetes.io/target-type"             = "ip"
#         "alb.ingress.kubernetes.io/group.name"              = "monitoring-ingress-group"
#       }
#     }
#     spec = {
#       rules = [
#         {
#           host = "prometheus.aws.wiktorowalski.pl"
#           http = {
#             paths = [
#               {
#                 path = "/"
#                 pathType = "Prefix"
#                 backend = {
#                   service = {
#                     name = "kube-prometheus-stack-prometheus"
#                     port = {
#                       number = 80
#                     }
#                   }
#                 }
#               }
#             ]
#           }
#         }
#       ]
#     }
#   }
# }

# resource "aws_route53_record" "grafana" {
#   zone_id = data.aws_route53_zone.zone.id
#   name    = "grafana.aws.${data.aws_route53_zone.zone.name}"
#   type    = "A"
#   alias {
#     name                   = aws_alb.eks.dns_name
#     zone_id                = aws_alb.eks.zone_id
#     evaluate_target_health = false
#   }
# }

# resource "aws_route53_record" "prometheus" {
#   zone_id = data.aws_route53_zone.zone.id
#   name    = "prometheus.aws.${data.aws_route53_zone.zone.name}"
#   type    = "A"
#   alias {
#     name                   = aws_alb.eks.dns_name
#     zone_id                = aws_alb.eks.zone_id
#     evaluate_target_health = false
#   }
# }
