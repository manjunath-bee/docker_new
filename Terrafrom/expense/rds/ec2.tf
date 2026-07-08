module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier = "demodb"

  engine            = "mysql"
  engine_version    = "8.0.44"
  instance_class    = "db.m5d.large"
  allocated_storage = 20

  db_name  = "transactions" # AWS will create this schema automatically
  username = "root"
  port     = "3306"
  manage_master_user_password = true

  vpc_security_group_ids = [data.aws_ssm_parameter.mysql_sg.value]

  tags = {
    Owner       = "user"
    Environment = "dev"
  }

  # DB subnet group
  create_db_subnet_group = false
  db_subnet_group_name = data.aws_ssm_parameter.subnet_group.value

  # DB parameter group
  family = "mysql8.0"

  # DB option group
  major_engine_version = "8.0"

  # Snapshot name upon DB deletion
  deletion_protection = false
  skip_final_snapshot = true

  parameters = [
    {
      name = "character_set_client"
      value = "utf8"
    },
    {
      name = "character_set_server"
      value = "utf8"
    }
  ]

  options = [
    {
      option_name = "MARIADB_AUDIT_PLUGIN"

      option_settings = [
        {
          name  = "SERVER_AUDIT_EVENTS"
          value = "CONNECT"
        },
        {
          name  = "SERVER_AUDIT_FILE_ROTATIONS"
          value = "37"
        },
      ]
    },
  ]
}

 resource "aws_route53_record" "database" {
      zone_id = "Z06028613BBM5PRD5PCHH"
      name = "mysql-dev.aws82s.online"
      type = "CNAME"
      ttl = "300"
      records = [module.db.db_instance_address]
   }