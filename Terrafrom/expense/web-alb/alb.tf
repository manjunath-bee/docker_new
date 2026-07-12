module "alb" {
  source = "terraform-aws-modules/alb/aws"
  name    = "web-alb"
  vpc_id  = data.aws_ssm_parameter.vpc_id.value
  subnets = split(",", data.aws_ssm_parameter.public_id.value)
  create_security_group = false
  security_groups = [data.aws_ssm_parameter.web_sg.value]
  enable_deletion_protection = false
  internal = false
  tags = {
    Environment = "Development"
    Project     = "Example"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = module.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_ssm_parameter.acm.value
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/html"
      message_body = "<h1>web application</h1>"
      status_code  = "200"
    }
  }
}

resource "aws_route53_record" "web" {
  zone_id = "Z06028613BBM5PRD5PCHH"
  name    = "*.aws82s.online"
  type    = "A"

  alias {
    name                   = module.alb.dns_name
    zone_id                = module.alb.zone_id
    evaluate_target_health = true
  }
}