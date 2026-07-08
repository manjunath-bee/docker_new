output "ec2_info"{
    value = aws_instance.example.public_ip
}