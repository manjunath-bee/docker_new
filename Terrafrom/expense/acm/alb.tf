resource "aws_acm_certificate" "cert" {
  domain_name       = "aws82s.online"
  validation_method = "DNS"

  tags = {
    Environment = "test"
  }
}