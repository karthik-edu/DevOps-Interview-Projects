# =============================================================================
# modules/ec2/main.tf
#
# Creates an Auto Scaling Group of nginx instances in private subnets:
#   - Security group (inbound HTTP:80 from ALB security group only)
#   - Launch template (Amazon Linux 2023, user-data installs nginx)
#   - Auto Scaling Group registered to the ALB target group
# =============================================================================

# --------------------------------------------------------------------------- #
# Latest Amazon Linux 2023 AMI
# --------------------------------------------------------------------------- #
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --------------------------------------------------------------------------- #
# Security Group — inbound HTTP from ALB only, all egress
# --------------------------------------------------------------------------- #
resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2-sg"
  vpc_id      = var.vpc_id
  description = "EC2: allow HTTP from ALB security group only"

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    description = "All outbound (for package installs via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-ec2-sg" })
}

# --------------------------------------------------------------------------- #
# Launch Template
# --------------------------------------------------------------------------- #
resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-lt-"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # Install nginx and serve a demo page identifying the instance
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
    echo '<html><body style="font-family:sans-serif;padding:2rem">
    <h1>Project 03 — Terraform AWS IaC</h1>
    <p><strong>Environment:</strong> ${var.environment}</p>
    <p><strong>Instance type:</strong> ${var.instance_type}</p>
    </body></html>' > /usr/share/nginx/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-instance" })
  }

  # Always create new template before destroying old one for zero-downtime
  lifecycle {
    create_before_destroy = true
  }
}

# --------------------------------------------------------------------------- #
# Auto Scaling Group
# --------------------------------------------------------------------------- #
resource "aws_autoscaling_group" "this" {
  name                = "${var.name}-asg"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Use ELB health checks so the ASG replaces unhealthy instances
  health_check_type         = "ELB"
  health_check_grace_period = 90

  tag {
    key                 = "Name"
    value               = "${var.name}-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
