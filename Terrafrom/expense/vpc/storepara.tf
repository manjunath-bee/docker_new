resource "aws_ssm_parameter" "main" {
  name  = "vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "public_id" {
  name  = "public_id"
  type  = "String"
  value = join(",", module.vpc.public_id)
}


resource "aws_ssm_parameter" "private_id" {
  name  = "private_id"
  type  = "String"
  value = join(",", module.vpc.private_id)
}


resource "aws_ssm_parameter" "subnet_group" {
  name  = "subnet_group"
  type  = "String"
  value = aws_db_subnet_group.main.name
}