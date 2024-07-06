# resource "aws_alb" "eks" {
#     name               = "eks-load-balancer"
#     internal           = false
#     load_balancer_type = "application"

#     subnets            = module.vpc.public_subnets
#     security_groups    = [aws_security_group.eks_lb.id, aws_security_group.eks_lb_2.id]
# }

# resource "aws_security_group" "eks_lb" {
#     name        = "eks-lb-sg"
#     description = "Security group for EKS load balancer"
#     vpc_id      = module.vpc.vpc_id

#     ingress {
#         from_port   = 80
#         to_port     = 80
#         protocol    = "TCP"
#         cidr_blocks = ["0.0.0.0/0"]
#     }

#     egress {
#         from_port   = 0
#         to_port     = 0
#         protocol    = "-1"
#         cidr_blocks = ["0.0.0.0/0"]
#     }
# }

# resource "aws_security_group" "eks_lb_2" {
#     name        = "eks-lb-sg-2"
#     description = "Security group for EKS load balancer"
#     vpc_id      = module.vpc.vpc_id

#     ingress {
#         from_port   = 443
#         to_port     = 443
#         protocol    = "TCP"
#         cidr_blocks = ["0.0.0.0/0"]
#     }

#     egress {
#         from_port   = 0
#         to_port     = 0
#         protocol    = "-1"
#         cidr_blocks = ["0.0.0.0/0"]
#     }
# }
