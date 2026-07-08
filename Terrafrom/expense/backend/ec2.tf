resource "aws_instance" "example" {
  ami                    = "ami-00b6288e85377e730"
  instance_type          = "t3.large"
  vpc_security_group_ids = [data.aws_ssm_parameter.backend_sg.value]
  subnet_id = split(",", data.aws_ssm_parameter.public_id.value)[0]
  associate_public_ip_address = true
  key_name = "balu"
  tags = {
    Name = "HelloWorld"
  }
}

resource "null_resource" "cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    instance_id = aws_instance.example.id
  }

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  
  connection {
  host        = aws_instance.example.public_ip
  type        = "ssh"
  user        = "ec2-user"
  private_key = file("C:/Users/manjungj/Downloads/BALU.pem")
}

  provisioner "file" {
    source      = "backend.sh"
    destination = "/tmp/backend.sh"
  }

  provisioner "remote-exec" {
    # Bootstrap script called with private_ip of each node in the cluster
    inline = [
      "chmod +x /tmp/backend.sh",
      "sudo sh /tmp/backend.sh ${var.environment}"
    ]
  }
}