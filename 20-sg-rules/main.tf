# mongobd accepting connection from catalogue on port number 27017
resource "aws_vpc_security_group_ingress_rule" "mongodb_catalogue" {
  security_group_id = local.mongodb_sg_id #destination

  referenced_security_group_id = local.catalogue_sg_id #source
  from_port                    = 27017
  ip_protocol                  = "tcp"
  to_port                      = 27017


}
