resource "aws_security_group" "allow_tls" {
  name        = "allow_tls-${terraform.workspace}"
  description = "Allow TLS inbound traffic and all outbound"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls-${terraform.workspace}"
  }
}

resource "aws_instance" "example" {
  ami                    = "ami-0220d79f3f480ecf5"
  instance_type          = lookup(var.instance_type,terraform.workspace)
  vpc_security_group_ids = [aws_security_group.allow_tls.id]

  tags = {
    Name = "HelloWorld"
  }
}
