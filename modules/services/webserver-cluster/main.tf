terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}


resource "aws_launch_configuration" "example" {
  image_id        = "ami-03fd5809787d564a0"
  instance_type   = var.instance_type
  security_groups = [aws_security_group.instance.id]
  user_data       = templatefile("${path.module}/user-data.sh", {
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  })

  # Required when using a launch configuration with an auto scaling group.
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  name                 = "${var.cluster_name}-terraform-asg"
  max_size             = var.max_size
  min_size             = var.min_size
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-terraform-asg"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.custom_tags

    content {
      key = tag.key
      value = tag.value
      propagate_at_launch = true
    }
  }
}


resource "aws_autoscaling_schedule" "scale_out_during_business_hours" {
  count = var.enable_autscaling ? 1 : 0

  depends_on             = [module.webserver-cluster.asg_name]
  autoscaling_group_name = module.webserver-cluster.asg_name
  scheduled_action_name  = "scale-out-during-business-hours"
  min_size               = 2
  max_size               = 10
  desired_capacity       = 10
  recurrence             = "0 9 * * *"
}

resource "aws_autoscaling_schedule" "scale_in_at_night" {
  count = var.enable_autscaling ? 1 : 0
  
  depends_on             = [module.webserver-cluster.asg_name]
  autoscaling_group_name = module.webserver-cluster.asg_name
  scheduled_action_name  = "scale-in-at-night"
  min_size               = 2
  max_size               = 10
  desired_capacity       = 2
  recurrence             = "0 17 * * *"
}

resource "aws_lb" "example" {
  name               = "${var.cluster_name}-asg-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = local.http_port
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

resource "aws_lb_target_group" "asg" {
  name     = "${var.cluster_name}-asg-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}


resource "aws_security_group" "instance" {
  name = "${var.cluster_name}-terraform-asg-instance"
}

resource "aws_security_group_rule" "allow_http_inbound_to_instance" {
  type              = "ingress"
  cidr_blocks       = local.all_ips
  from_port         = var.server_port
  protocol          = local.tcp_protocol
  security_group_id = aws_security_group.instance.id
  to_port           = var.server_port
  description       = "Allow inbound traffic to the ASG instances Security Group rule"
}

resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-terraform-sg"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = local.http_port
  to_port           = local.http_port
  protocol          = local.tcp_protocol
  cidr_blocks       = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id
  from_port         = local.any_port
  to_port           = local.any_port
  protocol          = local.any_protocol
  cidr_blocks       = local.all_ips
}
