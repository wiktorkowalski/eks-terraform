# module "db" {
#   source  = "terraform-aws-modules/rds/aws"
#   version = "6.5.5"

#   identifier = "demo"

#   engine         = "postgres"
#   engine_version = "16.2"
#   family        = "postgres16"
#   allow_major_version_upgrade = false
#   auto_minor_version_upgrade  = true

#   instance_class          = "db.t4g.micro"
#   allocated_storage       = 5
#   backup_retention_period = 0
#   backup_window           = "03:00-05:00"

#   db_name  = "postgres"
#   username = "postgres"
#   port     = "5432"

#   iam_database_authentication_enabled = true

#   db_subnet_group_name = module.vpc.database_subnet_group_name

#   subnet_ids             = module.vpc.database_subnets
#   vpc_security_group_ids = [aws_security_group.db.id]
# }

# resource "aws_security_group" "db" {
#   name        = "db-sg"
#   description = "Security group for RDS database"
#   vpc_id      = module.vpc.vpc_id

#   ingress {
#     from_port   = 5432
#     to_port     = 5432
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }
