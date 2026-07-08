data "aws_ssm_parameter" "alb_sg" {
  name = "alb_sg"
}

data "aws_ssm_parameter" "private_id" {
  name = "private_id"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "vpc_id"
}


