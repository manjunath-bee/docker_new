resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound"

# Example usage in security group:
dynamic "ingress" {
  for_each = local.inbound_ports
  content {
    from_port   = ingress.value
    to_port     = ingress.value
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

dynamic "egress" {
  for_each = local.outbound_ports
  content {
    from_port   = egress.value
    to_port     = egress.value
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_instance" "example" {
  ami                    = local.ami
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.allow_tls.id]

  tags = {
    Name = "HelloWorld"
  }
}
