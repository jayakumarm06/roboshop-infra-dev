resource "aws_instance" "catalogue" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = local.private_subnet_id
  vpc_security_group_ids = [local.catalogue_sg_id]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-catalogue"
    }
  )
}
resource "terraform_data" "bootstrap" {
  triggers_replace = [
    aws_instance.catalogue.id
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.catalogue.private_ip
  }
  provisioner "file" {
    source      = "${path.module}/bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh catalogue ${var.environment} ${var.app_version}"

    ]
  }
}

#stop the instance to prepare the AMI
#Note: here 3rd resource is not dependent on 2nd resource that is why we are creating dependncy here
resource "aws_ec2_instance_state" "catalogue" {
  instance_id = aws_instance.catalogue.id
  state       = "stopped"

  depends_on = [terraform_data.bootstrap]
}

## creating the AMI catalogue
resource "aws_ami_from_instance" "catalogue" {
  name               = "${local.common_name}-catalogue-${var.app_version}-${aws_instance.catalogue.id}" #roboshop-dev-catalogue-v4-instance_id
  source_instance_id = aws_ec2_instance_state.catalogue.id

  depends_on = [aws_ec2_instance_state.catalogue]
  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-catalogue-${var.app_version}-${aws_instance.catalogue.id}" #roboshop-dev-catalogue-v4-instance_id
    }
  )
}
