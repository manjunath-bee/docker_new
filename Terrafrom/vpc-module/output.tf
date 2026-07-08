output "az_info"{
    value = data.aws_availability_zones.available
}

output "public_info"{
    value = aws_subnet.public
}

output "vpc_id" {
    value = aws_vpc.main.id
}

output "public_id" {
    value = aws_subnet.public[*].id
}


output "private_id" {
    value = aws_subnet.private[*].id
}