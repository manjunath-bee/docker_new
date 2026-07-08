module "vpc" {
  source         = "../../vpc-module"
  cidr_block     = "10.0.0.0/16"
  comman_tag     = { project = "expense_dev" }
  cidr_block_public = ["10.0.1.0/24","10.0.2.0/24"]
  cidr_block_private = ["10.0.11.0/24","10.0.12.0/24"]
  is_peering = true
}

resource "aws_db_subnet_group" "main" {
  name       = "subnet-group"
  subnet_ids = module.vpc.private_id

  tags = {
    Name = "My DB subnet group"
  }
}

