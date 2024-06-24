# resource "kubernetes_ingress_v1" "grafana" {
#   metadata {
#     name      = "grafana-ingress"
#     namespace = "kube-prometheus-stack"
#     annotations = {
#       "alb.ingress.kubernetes.io/scheme"                  = "internet-facing"
#       "alb.ingress.kubernetes.io/target-group-attributes" = "stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=86400"
#       "alb.ingress.kubernetes.io/listen-ports"            = "[{\"HTTP\": 80}]"
#       "alb.ingress.kubernetes.io/actions.ssl-redirect"    = "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
#       "alb.ingress.kubernetes.io/target-type"             = "ip"
#       "alb.ingress.kubernetes.io/scheme"                  = "internet-facing"
#       "alb.ingress.kubernetes.io/healthcheck-path"        = "/api/health"
#       "kubernetes.io/ingress.class"                       = "alb"
#     }
#   }
#   spec {
#     ingress_class_name = "alb"
#     rule {
#       host = "grafana.aws.wiktorkowalski.pl"
#       http {
#         path {
#           path = "/*"
#           backend {
#             service {
#               name = "kube-prometheus-stack-grafana"
#               port {
#                 number = 3000
#               }
#             }
#           }
#         }
#       }
#     }
#   }
# }

# resource "kubernetes_ingress_v1" "prometheus" {
#   metadata {
#     name      = "prometheus-ingress"
#     namespace = "kube-prometheus-stack"
#     annotations = {
#       "alb.ingress.kubernetes.io/scheme"                  = "internet-facing"
#       "alb.ingress.kubernetes.io/target-group-attributes" = "stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=86400"
#       "alb.ingress.kubernetes.io/listen-ports"            = "[{\"HTTP\": 80}]"
#       "alb.ingress.kubernetes.io/actions.ssl-redirect"    = "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
#       "kubernetes.io/ingress.class" = "alb"
#     }
#   }
#   spec {
#     rule {
#       host = "prometheus.aws.wiktorkowalski.pl"
#       http {
#         path {
#           path = "/*"
#           backend {
#             service {
#               name = "kube-prometheus-stack-prometheus"
#               port {
#                 number = 9090
#               }
#             }
#           }
#         }
#       }
#     }
#   }
# }

# resource "aws_route53_record" "grafana" {
#   zone_id = data.aws_route53_zone.zone.id
#   name    = "grafana.aws.${data.aws_route53_zone.zone.name}"
#   type    = "A"
#   alias {
#     name                   = aws_lb.alb.dns_name
#     zone_id                = aws_lb.alb.zone_id
#     evaluate_target_health = false
#   }
# }

# resource "aws_route53_record" "prometheus" {
#   zone_id = data.aws_route53_zone.zone.id
#   name    = "prometheus.aws.${data.aws_route53_zone.zone.name}"
#   type    = "A"
#   alias {
#     name                   = aws_lb.alb.dns_name
#     zone_id                = aws_lb.alb.zone_id
#     evaluate_target_health = false
#   }
# }