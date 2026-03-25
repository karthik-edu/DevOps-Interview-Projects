# =============================================================================
# modules/alb/main.tf
#
# Creates a public-facing Application Load Balancer with:
#   - Security group (inbound HTTP:80 from internet)
#   - ALB in public subnets
#   - Target group with HTTP health checks
#   - HTTP:80 listener forwarding to the target group
# =============================================================================

# --------------------------------------------------------------------------- #
# Security Group — allows inbound HTTP from internet, all egress
# --------------------------------------------------------------------------- #
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  vpc_id      = var.vpc_id
  description = "ALB: allow inbound HTTP from internet"

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })
}

# --------------------------------------------------------------------------- #
# Application Load Balancer
# --------------------------------------------------------------------------- #
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Enable deletion protection in production; off here for easy teardown
  enable_deletion_protection = false

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

# --------------------------------------------------------------------------- #
# Target Group
# --------------------------------------------------------------------------- #
resource "aws_lb_target_group" "this" {
  name     = "${var.name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = var.tags
}

# --------------------------------------------------------------------------- #
# HTTP Listener
# --------------------------------------------------------------------------- #
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
