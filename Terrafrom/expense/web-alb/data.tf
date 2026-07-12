data "aws_ssm_parameter" "web_sg" {
  name = "web_sg"
}

data "aws_ssm_parameter" "public_id" {
  name = "public_id"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "vpc_id"
}


data "aws_ssm_parameter" "acm" {
  name = "acm"
}



