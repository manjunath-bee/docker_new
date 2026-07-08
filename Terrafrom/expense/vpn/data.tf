data "aws_ssm_parameter" "vpn_sg" {
  name = "vpn_sg"
}

data "aws_ssm_parameter" "public_id" {
  name = "public_id"
}