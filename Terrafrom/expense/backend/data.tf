data "aws_ssm_parameter" "backend_sg" {
  name = "backend_sg"
}


data "aws_ssm_parameter" "private_id" {
  name = "private_id"
}


data "aws_ssm_parameter" "vpc_id" {
  name = "vpc_id"
}


data "aws_ssm_parameter" "alb_listener" {
  name = "alb_listener"
}