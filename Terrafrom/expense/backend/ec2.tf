resource "aws_instance" "example" {
  ami                    = "ami-00b6288e85377e730"
  instance_type          = "t3.large"
  vpc_security_group_ids = [data.aws_ssm_parameter.backend_sg.value]
  subnet_id              = split(",", data.aws_ssm_parameter.private_id.value)[0]
  key_name               = "balu"

  user_data = <<-EOF
    #!/bin/bash
    sudo dnf install ansible-core -y
    ansible-galaxy collection install community.general community.mysql
    ansible-pull -i localhost, -U https://github.com/manjunath-bee/docker_new.git -d /tmp/ansible-repo anisible-tf/main.yaml -e COMPONENT=backend -e ENVIRONMENT=${var.environment}
  EOF

  tags = {
    Name = "HelloWorld"
  }
}
