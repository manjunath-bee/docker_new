locals {
  ami = data.aws_ami.example.id
  inbound_ports = [80, 443]
  outbound_ports = [443, 1433]
}
