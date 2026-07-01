variable "ec2_info" {
  type        = list
  default     = ["prod","test","staging"]
}

variable "comman_tags" {
  type        = map
  default     = {
      project = "expense"
  }
}

variable "env" {
  
}




