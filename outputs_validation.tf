
resource "terraform_data" "deployment_validation" {

  triggers_replace = {
    alb_dns = aws_lb.app.dns_name
    asg_id  = aws_autoscaling_group.asg.id
  }

  depends_on = [
    aws_lb_listener_rule.service1_rule,
    aws_lb_listener_rule.service2_rule,
    aws_autoscaling_group.asg
  ]

  provisioner "local-exec" {
    # This command passes the DNS as the first argument (sys.argv[1])
    command     = "python validate_endpoints.py ${aws_lb.app.dns_name}"
    interpreter = ["PowerShell", "-Command"]
  }
}