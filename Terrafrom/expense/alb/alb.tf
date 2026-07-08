module "alb" {
  source = "terraform-aws-modules/alb/aws"
  name    = "my-alb"
  vpc_id  = data.aws_ssm_parameter.vpc_id.value
  subnets = split(",", data.aws_ssm_parameter.private_id.value)
  create_security_group = false
  security_groups = [data.aws_ssm_parameter.alb_sg.value]
  enable_deletion_protection = false
  internal = true
  tags = {
    Environment = "Development"
    Project     = "Example"
  }
}



resource "aws_lb_listener" "front_end" {
  load_balancer_arn = module.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/html"
      message_body = "<h1>manju</h1>"
      status_code  = "200"
    }
  }
}

resource "aws_route53_record" "www" {
  zone_id = "Z06028613BBM5PRD5PCHH"
  name    = "*.dev.aws82s.online"
  type    = "A"

  alias {
    name                   = module.alb.dns_name
    zone_id                = module.alb.zone_id
    evaluate_target_health = true
  }
}