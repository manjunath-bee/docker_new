resource "aws_instance" "vpn" {
  ami                    = "ami-0faf1f05eb1858879"
  instance_type          = lookup(var.instance_type,terraform.workspace)
  vpc_security_group_ids = [data.aws_ssm_parameter.vpn_sg.value]
  subnet_id = split(",", data.aws_ssm_parameter.public_id.value)[0]
  associate_public_ip_address = true
  user_data = file("user-data.sh")
  key_name = "balu"
  tags = {
    Name = "HelloWorld"
  }
}

output "public_id" {
  value = aws_instance.vpn.public_ip
}