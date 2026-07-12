resource "aws_instance" "example" {
  ami                    = "ami-00b6288e85377e730"
  instance_type          = "t3.large"
  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg.value]
  subnet_id = split(",", data.aws_ssm_parameter.public_id.value)[0]
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
    source      = "frontend.sh"
    destination = "/tmp/frontend.sh"
  }

  provisioner "remote-exec" {
    # Bootstrap script called with private_ip of each node in the cluster
    inline = [
      "chmod +x /tmp/frontend.sh",
      "sudo sh /tmp/frontend.sh ${var.environment}"
    ]
  }
}


resource "null_resource" "stop_instance" {
  depends_on = [null_resource.cluster]

  provisioner "local-exec" {
    command = "aws ec2 stop-instances --instance-ids ${aws_instance.example.id} --region us-east-2 && aws ec2 wait instance-stopped --instance-ids ${aws_instance.example.id} --region us-east-2"
  }
}

resource "aws_ami_from_instance" "example" {
  name               = "terraform-web-example"
  source_instance_id = aws_instance.example.id
  depends_on         = [null_resource.stop_instance]
}

resource "null_resource" "terminate" {
  depends_on = [aws_ami_from_instance.example]

  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.example.id} --region us-east-2"
  }
}

resource "aws_lb_target_group" "web-tg" {
  name     = "tf-example-lb-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.value

  health_check {
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    matcher             = "200-299"
  }
}

resource "aws_launch_template" "web-example" {
  name                                 = "web-example"
  image_id                             = aws_ami_from_instance.example.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "t2.micro"
  key_name                             = "balu"
  update_default_version               = true
  vpc_security_group_ids               = [data.aws_ssm_parameter.frontend_sg.value]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "test"
    }
  }
}

resource "aws_autoscaling_group" "web-bar" {
  name                      = "foobar3-terraform-web-test"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 180
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  target_group_arns         = [aws_lb_target_group.web-tg.arn]
  vpc_zone_identifier       = split(",", data.aws_ssm_parameter.public_id.value)

  launch_template {
    id      = aws_launch_template.web-example.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "backend-asg"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }
}

resource "aws_lb_listener_rule" "web-static" {
  listener_arn = data.aws_ssm_parameter.web_listener.value
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-tg.arn
  }

  condition {
    host_header {
      values = ["frontend.aws82s.online"]
    }
  }
}

