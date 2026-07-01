resource "aws_route53_record" "www" {
  for_each = { for idx, name in var.ec2_info : name => aws_instance.example[idx] }
  name     = each.key == "staging" ? "staging.${var.env}.aws82s.online" : "${each.key}-${var.env}.aws82s.online"
  zone_id  = "Z06028613BBM5PRD5PCHH"
  type     = "A"
  ttl      = 300
  records  = [each.key == "staging" ? each.value.public_ip : each.value.private_ip]
}
