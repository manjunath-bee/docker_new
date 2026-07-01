variable "instance_type" {
  type        = map
  default     = {
    mysql = "t2.micro"
    backend = "t3.small"
    frontend = "t3.large"
  }
}
