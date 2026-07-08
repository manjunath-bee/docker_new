output "az_info"{
    value = module.vpc.az_info
}

output "public_info"{
    value = module.vpc.public_info
}

output "vpc_id"{
    value = module.vpc.vpc_id
}

output "public_id"{
    value = module.vpc.public_id
}

output "priavate_info"{
    value = module.vpc.private_id
}