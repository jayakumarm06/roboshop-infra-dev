resource "aws_instance" "user" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = local.private_subnet_id
  vpc_security_group_ids = [local.user_sg_id]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-user"
    }
  )
}
resource "terraform_data" "bootstrap" {
  triggers_replace = [
    aws_instance.user.id
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.user.private_ip
  }
  provisioner "file" {
    source      = "${path.module}/bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh user ${var.environment} ${var.app_version}"

    ]
  }
}

#stop the instance to prepare the AMI
#Note: here 3rd resource is not dependent on 2nd resource that is why we are creating dependncy here
resource "aws_ec2_instance_state" "user" {
  instance_id = aws_instance.user.id
  state       = "stopped"

  depends_on = [terraform_data.bootstrap]
}

## creating the AMI user
resource "aws_ami_from_instance" "user" {
  name               = "${local.common_name}-user-${var.app_version}-${aws_instance.user.id}" #roboshop-dev-user-v4-instance_id
  source_instance_id = aws_ec2_instance_state.user.id

  depends_on = [aws_ec2_instance_state.user]
  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-user-${var.app_version}-${aws_instance.user.id}" #roboshop-dev-user-v4-instance_id
    }
  )
}

#launch Template
resource "aws_launch_template" "user" {
  name = "${local.common_name}-user"


  image_id                             = aws_ami_from_instance.user.id
  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t3.micro"

  vpc_security_group_ids = [local.user_sg_id]
  update_default_version = true

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name}-user"
      }
    )
  }
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name}-user"
      }
    )
  }
}

#target_group
resource "aws_lb_target_group" "user" {
  name                 = "${local.common_name}-user"
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
resource "aws_autoscaling_group" "user" {
  name                      = "${local.common_name}-user"
  max_size                  = 5   #autoscaling can create max upto 5 instances
  min_size                  = 1   # All the time,it should maintain atleast 1
  health_check_grace_period = 120 #120 sec ,autoscaling will not do healtchecks
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  launch_template {
    id      = aws_launch_template.user.id
    version = "$Latest"
  }
  vpc_zone_identifier = local.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.user.arn]

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
        Name = "${local.common_name}-user"
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

resource "aws_autoscaling_policy" "user" {
  name                   = "${local.common_name}-user"
  autoscaling_group_name = aws_autoscaling_group.user.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }

}

#listner_rule
# Note:1: while created user doesnt create listeners rule 
# 2:->user targetgroup created then autoscaling instance launche the target group  then you created listener rules

resource "aws_lb_listener_rule" "user" {
  listener_arn = local.backend_alb_listener_arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user.arn
  }

  condition {
    host_header {
      values = ["user.backend-alb-${var.environment}.${var.domain_name}"]
    }
  }
}

#Already stopped instance there now delete/terminate the instance

# aws ec2 terminate-instances --instance-ids i-0123456789abcdef0
resource "terraform_data" "user_delete" {
  triggers_replace = [
    aws_instance.user.id
  ]
  depends_on = [aws_autoscaling_policy.user]

  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.user.id}"

  }
}
