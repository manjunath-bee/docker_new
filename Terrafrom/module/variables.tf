variable "ami" {
    default = "ami-0220d79f3f480ecf5"
}

variable "instance_type" {
    default = "t3.small"
    validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "m5.large", "r5.xlarge"], var.instance_type)
    error_message = "Valid values for instance_type are: t3.micro, t3.small, t3.medium, m5.large, r5.xlarge."
  }
}

