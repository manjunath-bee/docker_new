resource "aws_instance" "example" {
  ami                    = "ami-00b6288e85377e730"
  instance_type          = lookup(var.instance_type,terraform.workspace)
  vpc_security_group_ids = [data.aws_ssm_parameter.backend_sg.value]
  subnet_id = split(",", data.aws_ssm_parameter.private_id.value)[0]
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
    host = aws_instance.example.id
  }

  provisioner "remote-exec" {
    # Bootstrap script called with private_ip of each node in the cluster
    inline = [
      "bootstrap-cluster.sh ${join(" ",
      aws_instance.cluster[*].private_ip)}",
    ]
  }
}