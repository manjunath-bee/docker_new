resource "aws_ssm_parameter" "alb_listener" {
  name  = "alb_listener"
  type  = "String"
  value = aws_lb_listener.front_end.arn
  overwrite = true
}
