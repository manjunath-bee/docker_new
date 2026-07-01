resource "aws_instance" "my_vm" {
 ami           = "ami-0220d79f3f480ecf5"
 instance_type = "t3.small"
 
 provisioner "local-exec" {
   command = "echo ${self.private_ip} >> private_ip.txt"
 }
 
 tags = {
   Name = var.name_tag,
 }
}