data "aws_ami" "example" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["devops-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

output "xxx" {
  value = data.aws_ami.example.id
}
