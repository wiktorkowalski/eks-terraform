resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana-ingress"
    namespace = "kube-prometheus-stack"
    annotations = {
      "kubernetes.io/ingress.class" : "alb"
      "alb.ingress.kubernetes.io/scheme" : "internet-facing"
      # "alb.ingress.kubernetes.io/listen-ports" : "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      # "alb.ingress.kubernetes.io/certificate-arn" : aws_acm_certificate.grafana_cert.arn
      # "alb.ingress.kubernetes.io/ssl-policy" : "ELBSecurityPolicy-2016-08"
      "alb.ingress.kubernetes.io/target-type" : "ip"
      "alb.ingress.kubernetes.io/healthcheck-path" : "/api/health"
      "cert-manager.io/cluster-issuer" : "letsencrypt"
    }
  }

  spec {
    rule {
      host = "grafana.aws.wiktorkowalski.pl"
      http {
        path {
          path = "/*"
          # path_type = "prefix"
          backend {
            service {
              name = "kube-prometheus-stack-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    tls {
      hosts       = ["grafana.aws.wiktorkowalski.pl"]
      secret_name = "grafana-tls"
    }
  }
}
