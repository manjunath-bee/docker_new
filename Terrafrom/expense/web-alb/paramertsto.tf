resource "aws_ssm_parameter" "web_listener" {
  name  = "web_listener"
  type  = "String"
  value = aws_lb_listener.front_end.arn
  overwrite = true
}
