resource "aws_ssm_parameter" "mysql_sg" {
  name  = "mysql_sg"
  type  = "String"
  value = module.mysql_sg.sg_id
  overwrite = true
}

resource "aws_ssm_parameter" "backend_sg" {
  name  = "backend_sg"
  type  = "String"
  value = module.backend_sg.sg_id
  overwrite = true
}


resource "aws_ssm_parameter" "bashost_sg" {
  name  = "bashost_sg"
  type  = "String"
  value = module.bashost_sg.sg_id
  overwrite = true
}

resource "aws_ssm_parameter" "alb_sg" {
  name  = "alb_sg"
  type  = "String"
  value = module.alb_sg.sg_id
  overwrite = true
}

resource "aws_ssm_parameter" "vpn_sg" {
  name  = "vpn_sg"
  type  = "String"
  value = module.vpn_sg.sg_id
  overwrite = true
}