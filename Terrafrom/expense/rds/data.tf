data "aws_ssm_parameter" "mysql_sg" {
  name = "mysql_sg"
}


data "aws_ssm_parameter" "subnet_group" {
  name = "subnet_group"
}