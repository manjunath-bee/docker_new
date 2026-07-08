data "aws_ssm_parameter" "backend_sg" {
  name = "backend_sg"
}


data "aws_ssm_parameter" "public_id" {
  name = "public_id"
}