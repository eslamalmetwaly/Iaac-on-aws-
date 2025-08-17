provider "aws" { 
   region = "us-east-1"
  }

data "terraform_remote_state" "infra" {
  backend = "local"

  config = {
    path = "../terraform.tfstate"
  }
}

data "http" "myip" {
  url = "http://checkip.amazonaws.com/"
}

resource "aws_security_group" "private_ec2_sg" {

  name        = "private_ec2_sg"
  description = "Allow some traffics "
  vpc_id      = data.terraform_remote_state.infra.outputs.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [data.terraform_remote_state.infra.outputs.bastionSG_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2_sg"
  }
}

resource "aws_instance" "web" {
     ami                    = "ami-020cba7c55df1f615"
     instance_type          = "t2.micro"
     key_name               = "bt-key"
     subnet_id              = data.terraform_remote_state.infra.outputs.private_subnet_1_id
     vpc_security_group_ids = [aws_security_group.private_ec2_sg.id]
     tags = { 
             Name = "web"
            }
}

# ALB_SG
resource "aws_security_group" "alb_sg" {
  name = " ALB_SG "
  description = " distribute traffics from internet to machines "
  vpc_id = data.terraform_remote_state.infra.outputs.vpc_id  

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb_sg"
  }
}

# create load balancer 

  resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false  # means that load balancer takes public ip , if no LB don't take public ip 
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [data.terraform_remote_state.infra.outputs.public_subnet_2_id, data.terraform_remote_state.infra.outputs.public_subnet_1_id]

  tags = {
    Name = "app-alb"
  }
}

# creation target grroup 
resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.infra.outputs.vpc_id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = {
    Name = "app_tg"
  }
}

#Create listner 
resource "aws_lb_listener" "app_alb_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}








































