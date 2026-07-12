module "mysql_sg" {
  source         = "../../sg-module"
  env = "mysql"
}


resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = module.mysql_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

module "backend_sg" {
  source         = "../../sg-module"
  env = "backend"
}

resource "aws_vpc_security_group_egress_rule" "backend_sg" {
  security_group_id = module.backend_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

module "bashost_sg" {
  source         = "../../sg-module"
  env = "bashost"
}

resource "aws_vpc_security_group_egress_rule" "bashost_sg" {
  security_group_id = module.bashost_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

module "alb_sg" {
  source         = "../../sg-module"
  env = "alb"
}

resource "aws_vpc_security_group_egress_rule" "alb_sg" {
  security_group_id = module.alb_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}


resource "aws_security_group_rule" "alb_bashhost" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  source_security_group_id  = module.bashost_sg.sg_id
  security_group_id = module.alb_sg.sg_id
}


resource "aws_security_group_rule" "sg_bashhost" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks        = ["122.169.152.227/32"]
  security_group_id = module.bashost_sg.sg_id
}

module "vpn_sg" {
  source         = "../../sg-module"
  env = "vpn"
}

resource "aws_vpc_security_group_egress_rule" "vpn_sg" {
  security_group_id = module.vpn_sg.sg_id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}


resource "aws_security_group_rule" "vpn_22" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.vpn_sg.sg_id
}

resource "aws_security_group_rule" "vpn_443" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.vpn_sg.sg_id
}

resource "aws_security_group_rule" "vpn_1194" {
  type              = "ingress"
  from_port         = 1194
  to_port           = 1194
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.vpn_sg.sg_id
}

resource "aws_security_group_rule" "vpn_943" {
  type              = "ingress"
  from_port         = 943
  to_port           = 943
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.vpn_sg.sg_id
}

resource "aws_security_group_rule" "alb_vpn" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  source_security_group_id  = module.vpn_sg.sg_id
  security_group_id = module.alb_sg.sg_id
}

resource "aws_security_group_rule" "mysql_bashost" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  source_security_group_id  = module.bashost_sg.sg_id
  security_group_id = module.mysql_sg.sg_id
}

resource "aws_security_group_rule" "mysql_vpn" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  source_security_group_id  = module.vpn_sg.sg_id
  security_group_id = module.mysql_sg.sg_id
}

resource "aws_security_group_rule" "backend_vpn" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  source_security_group_id  = module.vpn_sg.sg_id
  security_group_id = module.backend_sg.sg_id
}

resource "aws_security_group_rule" "backend_sg_public" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks        = ["122.169.152.227/32"]
  security_group_id = module.backend_sg.sg_id
}


resource "aws_security_group_rule" "mysql_backend" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  source_security_group_id  = module.backend_sg.sg_id
  security_group_id = module.mysql_sg.sg_id
}


resource "aws_security_group_rule" "backend_alb" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  source_security_group_id  = module.alb_sg.sg_id
  security_group_id = module.backend_sg.sg_id
}

module "web_sg" {
  source         = "../../sg-module"
  env = "web"
}

resource "aws_security_group_rule" "web_sg" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks        = ["122.169.152.227/32"]
  security_group_id = module.web_sg.sg_id
}

module "frontend_sg" {
  source         = "../../sg-module"
  env = "frontend"
}


resource "aws_security_group_rule" "front_sg" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks        = ["122.169.152.227/32"]
  security_group_id = module.frontend_sg.sg_id
}


resource "aws_security_group_rule" "front_web_sg" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  source_security_group_id  = module.web_sg.sg_id
  security_group_id = module.frontend_sg.sg_id
}


resource "aws_security_group_rule" "alb_frontend_sg" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  source_security_group_id  = module.frontend_sg.sg_id
  security_group_id = module.alb_sg.sg_id
}

resource "aws_vpc_security_group_egress_rule" "frontend_sg" {
  security_group_id = module.frontend_sg.sg_id    # NOT frontend_sgcd
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}








