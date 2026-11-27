locals {
  ami_id         = data.aws_ami.name.id
  frontend_sg_id = data.aws_ssm_parameter.frontend_sg_id.value
  # private_subnet_id  = split(",", data.aws_ssm_parameter.private_subnet_ids.value)[0]
  # private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
  public_subnet_id  = split(",", data.aws_ssm_parameter.public_subnet_id.value)[0]
  public_subnet_ids = split(",", data.aws_ssm_parameter.public_subnet_ids.value)
  common_name       = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Terraform   = "true"

  }
  vpc_id                    = data.aws_ssm_parameter.vpc_id.value
  frontend_alb_listener_arn = data.aws_ssm_parameter.frontend_alb_listener_arn.value
}
