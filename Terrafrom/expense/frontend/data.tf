data "aws_ssm_parameter" "frontend_sg" {
  name = "frontend_sg"
}


data "aws_ssm_parameter" "public_id" {
  name = "public_id"
}


data "aws_ssm_parameter" "vpc_id" {
  name = "vpc_id"
}


data "aws_ssm_parameter" "web_listener" {
  name = "web_listener"
}