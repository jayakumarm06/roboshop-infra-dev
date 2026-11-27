resource "aws_instance" "payment" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = local.private_subnet_id
  vpc_security_group_ids = [local.payment_sg_id]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-payment"
    }
  )
}
resource "terraform_data" "bootstrap" {
  triggers_replace = [
    aws_instance.payment.id
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.payment.private_ip
  }
  provisioner "file" {
    source      = "${path.module}/bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh payment ${var.environment} ${var.app_version}"

    ]
  }
}

#stop the instance to prepare the AMI
#Note: here 3rd resource is not dependent on 2nd resource that is why we are creating dependncy here
resource "aws_ec2_instance_state" "payment" {
  instance_id = aws_instance.payment.id
  state       = "stopped"

  depends_on = [terraform_data.bootstrap]
}

## creating the AMI payment
resource "aws_ami_from_instance" "payment" {
  name               = "${local.common_name}-payment-${var.app_version}-${aws_instance.payment.id}" #roboshop-dev-payment-v4-instance_id
  source_instance_id = aws_ec2_instance_state.payment.id

  depends_on = [aws_ec2_instance_state.payment]
  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-payment-${var.app_version}-${aws_instance.payment.id}" #roboshop-dev-payment-v4-instance_id
    }
  )
}

#launch Template
resource "aws_launch_template" "payment" {
  name = "${local.common_name}-payment"


  image_id                             = aws_ami_from_instance.payment.id
  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t3.micro"

  vpc_security_group_ids = [local.payment_sg_id]
  update_default_version = true

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name}-payment"
      }
    )
  }
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name}-payment"
      }
    )
  }
}

#target_group
resource "aws_lb_target_group" "payment" {
  name                 = "${local.common_name}-payment"
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
resource "aws_autoscaling_group" "payment" {
  name                      = "${local.common_name}-payment"
  max_size                  = 5   #autoscaling can create max upto 5 instances
  min_size                  = 1   # All the time,it should maintain atleast 1
  health_check_grace_period = 120 #120 sec ,autoscaling will not do healtchecks
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  launch_template {
    id      = aws_launch_template.payment.id
    version = "$Latest"
  }
  vpc_zone_identifier = local.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.payment.arn]

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
        Name = "${local.common_name}-payment"
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

resource "aws_autoscaling_policy" "payment" {
  name                   = "${local.common_name}-payment"
  autoscaling_group_name = aws_autoscaling_group.payment.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }

}

#listner_rule
# Note:1: while created payment doesnt create listeners rule 
# 2:->payment targetgroup created then autoscaling instance launche the target group  then you created listener rules

resource "aws_lb_listener_rule" "payment" {
  listener_arn = local.backend_alb_listener_arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payment.arn
  }

  condition {
    host_header {
      values = ["payment.backend-alb-${var.environment}.${var.domain_name}"]
    }
  }
}

#Already stopped instance there now delete/terminate the instance

# aws ec2 terminate-instances --instance-ids i-0123456789abcdef0
resource "terraform_data" "payment_delete" {
  triggers_replace = [
    aws_instance.payment.id
  ]
  depends_on = [aws_autoscaling_policy.payment]

  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.payment.id}"

  }
}
