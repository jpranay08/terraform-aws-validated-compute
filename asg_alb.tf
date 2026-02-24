# --- ALB ---
resource "aws_lb" "app" {
  name                       = "${var.project_name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = aws_subnet.public[*].id
  enable_deletion_protection = false
  tags                       = local.common_tags
}

# --- Target Group for Service 1 ---
resource "aws_lb_target_group" "service1" {
  name        = "${var.project_name}-tg1"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }

  tags = local.common_tags
}

# --- Target Group for Service 2 ---
resource "aws_lb_target_group" "service2" {
  name        = "${var.project_name}-tg2"
  port        = 5001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }

  tags = local.common_tags
}

# ALB Listener (HTTP)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = 404
      message_body = "Not Found"
    }
  }
}

# Listener Rule for /service1
resource "aws_lb_listener_rule" "service1_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service1.arn
  }

  transform {
    type = "url-rewrite" # This was the missing required argument!

    url_rewrite_config {
      rewrite {
        regex   = "^/service1/(.*)"
        replace = "/$1"
      }
    }
  }

  condition {
    path_pattern {
      values = ["/service1*"]
    }
  }
}

# Listener Rule for /service2
resource "aws_lb_listener_rule" "service2_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service2.arn
  }

  transform {
    type = "url-rewrite" # This was the missing required argument!

    url_rewrite_config {
      rewrite {
        regex   = "^/service2/(.*)"
        replace = "/$1"
      }
    }
  }
  condition {
    path_pattern {
      values = ["/service2*"]
    }
  }
}

resource "aws_autoscaling_group" "asg" {
  name                = "${var.project_name}-asg"
  max_size            = 4
  min_size            = 2
  desired_capacity    = 2
  vpc_zone_identifier = aws_subnet.private[*].id
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns = [
    aws_lb_target_group.service1.arn,
    aws_lb_target_group.service2.arn
  ]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

# --- Auto Scaling Policy: CPU-based ---
resource "aws_autoscaling_policy" "cpu_scale_out" {
  name                   = "${var.project_name}-cpu-scale-out"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 40
  alarm_actions       = [aws_autoscaling_policy.cpu_scale_out.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}
