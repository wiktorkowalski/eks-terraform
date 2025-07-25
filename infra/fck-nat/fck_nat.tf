module "fck-nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "1.3.0"

  name      = "fck-nat"
  vpc_id    = data.aws_vpc.vpc.id
  subnet_id = data.aws_subnets.public.ids[0]

  use_cloudwatch_agent = true
  use_ssh              = true
  ssh_key_name         = "WiktorPC"

  update_route_tables = false # manual update
}

resource "aws_route" "nat_gateway" {
  count = length(data.aws_route_tables.route_tables.ids)

  route_table_id         = data.aws_route_tables.route_tables.ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.fck-nat.eni_id
}

resource "aws_route" "nat_gateway_default" {
  count = length(data.aws_route_tables.route_tables_default.ids)

  route_table_id         = data.aws_route_tables.route_tables_default.ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.fck-nat.eni_id
}

data "aws_vpc" "vpc" {
  tags = {
    Name = "${local.cluster_name}-vpc"
  }
}

data "aws_subnets" "public" {
  tags = {
    "public" = "true"
  }
}

data "aws_route_tables" "route_tables" {
  vpc_id = data.aws_vpc.vpc.id

  tags = {
    Name = "${local.cluster_name}-vpc-private-*"
  }
}

data "aws_route_tables" "route_tables_default" {
  vpc_id = data.aws_vpc.vpc.id

  tags = {
    Name = "${local.cluster_name}-vpc-default"
  }
}
