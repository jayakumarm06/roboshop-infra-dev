resource "aws_instance" "shipping" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = local.private_subnet_id
  vpc_security_group_ids = [local.shipping_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.shipping.name

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-shipping"
    }
  )
}
resource "terraform_data" "bootstrap" {
  triggers_replace = [
    aws_instance.shipping.id
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.shipping.private_ip
  }
  provisioner "file" {
    source      = "${path.module}/bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh shipping ${var.environment} ${var.app_version}"

    ]
  }
}

#stop the instance to prepare the AMI
#Note: here 3rd resource is not dependent on 2nd resource that is why we are creating dependncy here
resource "aws_ec2_instance_state" "shipping" {
  instance_id = aws_instance.shipping.id
  state       = "stopped"

  depends_on = [terraform_data.bootstrap]
}

## creating the AMI shipping
resource "aws_ami_from_instance" "shipping" {
  name               = "${local.common_name}-shipping-${var.app_version}-${aws_instance.shipping.id}" #roboshop-dev-shipping-v4-instance_id
  source_instance_id = aws_ec2_instance_state.shipping.id

  depends_on = [aws_ec2_instance_state.shipping]
  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-shipping-${var.app_version}-${aws_instance.shipping.id}" #roboshop-dev-shipping-v4-instance_id
    }
  )
}

#launch Template
resource "aws_launch_template" "shipping" {
  name = "${local.common_name}-shipping"


  image_id                             = aws_ami_from_instance.shipping.id
  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t3.micro"

  vpc_security_group_ids = [local.shipping_sg_id]
  update_default_version = true

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name}-shipping"
      }
    )
  }
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name}-shipping"
      }
    )
  }
}

#target_group
resource "aws_lb_target_group" "shipping" {
  name                 = "${local.common_name}-shipping"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = local.vpc_id
  deregistration_delay = 10

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    matcher             = "200-299"
    path                = "/health"
    port                = 8080
    protocol            = "HTTP"
    timeout             = 5
  }
}

#autoscaling group
resource "aws_autoscaling_group" "shipping" {
  name                      = "${local.common_name}-shipping"
  max_size                  = 5   #autoscaling can create max upto 5 instances
  min_size                  = 1   # All the time,it should maintain atleast 1
  health_check_grace_period = 120 #120 sec ,autoscaling will not do healtchecks
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  launch_template {
    id      = aws_launch_template.shipping.id
    version = "$Latest"
  }
  vpc_zone_identifier = local.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.shipping.arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  dynamic "tag" {
    for_each = merge(
      local.common_tags,
      {
        Name = "${local.common_name}-shipping"
      }
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }

  }

  timeouts {
    delete = "15m" #autoscaling to create the instance are not if itis failed the the limit 15mins
  }

}

#autoscaling policy

resource "aws_autoscaling_policy" "shipping" {
  name                   = "${local.common_name}-shipping"
  autoscaling_group_name = aws_autoscaling_group.shipping.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }

}

#listner_rule
# Note:1: while created shipping doesnt create listeners rule 
# 2:->shipping targetgroup created then autoscaling instance launche the target group  then you created listener rules

resource "aws_lb_listener_rule" "shipping" {
  listener_arn = local.backend_alb_listener_arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shipping.arn
  }

  condition {
    host_header {
      values = ["shipping.backend-alb-${var.environment}.${var.domain_name}"]
    }
  }
}

#Already stopped instance there now delete/terminate the instance

# aws ec2 terminate-instances --instance-ids i-0123456789abcdef0
resource "terraform_data" "shipping_delete" {
  triggers_replace = [
    aws_instance.shipping.id
  ]
  depends_on = [aws_autoscaling_policy.shipping]

  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.shipping.id}"

  }
}
