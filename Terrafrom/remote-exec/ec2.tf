resource "aws_instance" "my_vm" {
 ami           = "ami-0220d79f3f480ecf5"
 instance_type = "t3.small"
 
 provisioner "remote-exec" {
   inline = [
     "touch hello.txt",
     "echo 'Have a great day!' >> hello.txt"
   ]
 }
 
 tags = {
   Name = "manju"
 }
}