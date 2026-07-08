module "ec2" {
  source         = "../module"
  instance_type  = "t3.small"
}

output "public_ip"{
  value =module.ec2.ec2_info
}