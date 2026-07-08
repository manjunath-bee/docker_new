data "aws_ssm_parameter" "bashost_sg" {
  name = "bashost_sg"
}


data "aws_ssm_parameter" "public_id" {
  name = "public_id"
}