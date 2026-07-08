variable "cidr_block" {
    
}

variable "enable_dns_hostnames" {
    default = true
    
}

variable "comman_tag" {
    default = {
        project = "expense"
    }
    
}

variable "tags" {
    default = {
        env = "test"
    }
    
}

variable "cidr_block_public" {
    type = list
      validation {
    condition     = length(var.cidr_block_public) == 2
    error_message = "public subnet allow only 2"
  }    
}

variable "cidr_block_private" {
    type = list
      validation {
    condition     = length(var.cidr_block_private) == 2
    error_message = "private subnet allow only 2"
  }    
}

variable "is_peering" {
    default = false
}