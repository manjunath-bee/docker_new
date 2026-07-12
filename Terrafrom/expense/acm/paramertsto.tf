resource "aws_ssm_parameter" "acm" {
  name  = "acm"
  type  = "String"
  value = aws_acm_certificate.cert.arn
  overwrite = true
}
