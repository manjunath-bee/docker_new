output "instance_info" {
  value = aws_instance.example[*].private_ip
}
