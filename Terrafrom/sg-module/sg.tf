resource "aws_security_group" "allow_tls" {
  name        = "${var.project}-${var.env}-sg"
  description = "${var.project}-${var.env}-sg"
  vpc_id      = data.aws_ssm_parameter.main.value

  tags = {
    Name = "${var.project}-${var.env}-sg"
  }
}