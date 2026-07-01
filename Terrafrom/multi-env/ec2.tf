resource "aws_security_group" "allow_tls" {
  name        = "${var.comman_tags["project"]}-${var.env}"
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
    Name = "${var.comman_tags["project"]}-${var.env}"

  }
}

resource "aws_instance" "example" {
  count                  =  3
  ami                    = "ami-0220d79f3f480ecf5"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.allow_tls.id]

  tags = merge(var.comman_tags,{
    Name = "${var.comman_tags["project"]}-${var.env}-${var.ec2_info[count.index]}"
  })
}
