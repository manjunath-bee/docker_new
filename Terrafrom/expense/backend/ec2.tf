resource "aws_instance" "example" {
  ami                    = "ami-00b6288e85377e730"
  instance_type          = lookup(var.instance_type,terraform.workspace)
  vpc_security_group_ids = [data.aws_ssm_parameter.bashost_sg.value]
  subnet_id = split(",", data.aws_ssm_parameter.public_id.value)[0]
  associate_public_ip_address = true
  key_name = "balu"
  tags = {
    Name = "HelloWorld"
  }
}
