resource "aws_vpc" "main" {
  cidr_block       = var.cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames
  instance_tenancy = "default"

  tags =  merge(var.comman_tag,var.tags,{
    Name = "main"
  })
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}


resource "aws_subnet" "public" {
  count = length(var.cidr_block_public)
  vpc_id     = aws_vpc.main.id
  cidr_block = var.cidr_block_public[count.index]
  availability_zone = local.az_name[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-${var.cidr_block_public[count.index]}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.cidr_block_private)
  vpc_id     = aws_vpc.main.id
  cidr_block = var.cidr_block_private[count.index]
  availability_zone = local.az_name[count.index]

  tags = {
    Name = "private-${var.cidr_block_private[count.index]}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "nat-gateway-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # Replace with your public subnet ID

  tags = {
    Name = "main-nat-gateway"
  }

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public"
  }
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private"
  }
}

resource "aws_route" "public_r" {
  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
}

resource "aws_route" "priavte_r" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "example_public" {
  count = length(var.cidr_block_public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "example_private" {
  count = length(var.cidr_block_private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
