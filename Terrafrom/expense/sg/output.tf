output "sg_id" {
    value = module.mysql_sg.sg_id
}


output "backend_id" {
    value = module.backend_sg.sg_id
}

output "bashhost_id" {
    value = module.bashost_sg.sg_id
}