resource "aws_route53_record" "www" {
  for_each = aws_instance.example
  name     = each.key == "frontend" ? "aws82s.online" : "${each.key}.aws82s.online"
  zone_id  = "Z06028613BBM5PRD5PCHH"
  type     = "A"
  ttl      = 300
  records  = [each.key == "frontend" ? each.value.public_ip : each.value.private_ip]
}
