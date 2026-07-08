resource "aws_vpc_peering_connection" "foo" {
  count = var.is_peering ? 1 : 0
  peer_vpc_id   = aws_vpc.main.id
  vpc_id        = data.aws_vpc.default.id
}