provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

terraform {
  backend "s3" {
    bucket       = "s4117444-tfstate"
    key          = "terraform.tfstate"
    region       = "us-east-1"  
    use_lockfile = true
  }
}

resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  description = "ALB security group via Terraform"
  vpc_id = data.aws_vpc.default.id

  ingress{
    from_port = 80
    to_port = 80
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  description = "DB security group via Terraform"
  vpc_id = data.aws_vpc.default.id

  ingress{
    from_port = 5432
    to_port = 5432
    protocol = "tcp" 
    security_groups = [aws_security_group.backend_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "backend_sg" {
  name   = "backend-sg"
  description = "Backend security group via Terraform"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "frontend_sg" {
  name   = "frontend-sg"
  description = "Frontend security group via Terraform"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 8081
    to_port = 8081
    protocol = "tcp" 
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "tls_private_key" "ssh_key"{
    algorithm = "RSA"
    rsa_bits = 2048
}

resource "aws_key_pair" "public_key"{
    key_name = "posts-key"
    public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "local_file" "private_key"{
    content = tls_private_key.ssh_key.private_key_pem
    filename        = "${path.module}/private-posts-key.pem"
    file_permission = "0400"
}

resource "aws_instance" "db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.public_key.key_name
  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true

  tags = {
    Name = "posts-db"
  }
}

resource "aws_instance" "backend" {
  count = 2
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.public_key.key_name
  vpc_security_group_ids      = [aws_security_group.backend_sg.id]
  subnet_id                   = data.aws_subnets.default.ids[count.index]
  associate_public_ip_address = true

  tags = {
    Name = "posts-backend"
  }
}

resource "aws_instance" "frontend" {
  count = 2
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.public_key.key_name
  vpc_security_group_ids      = [aws_security_group.frontend_sg.id]
  subnet_id                   = data.aws_subnets.default.ids[count.index]
  associate_public_ip_address = true

  tags = {
    Name = "posts-frontend"
  }
}

resource "aws_lb" "frontend_alb" {
    name            = "frontend-alb"
    internal        = false
    ip_address_type     = "ipv4"
    load_balancer_type = "application"
    security_groups = [aws_security_group.alb_sg.id]
    subnets = data.aws_subnets.default.ids
    tags = {
        Name = "frontend-alb"
    }
}

resource "aws_lb" "backend_alb" {
    name            = "backend-alb"
    internal        = false
    ip_address_type     = "ipv4"
    load_balancer_type = "application"
    security_groups = [aws_security_group.alb_sg.id]
    subnets = data.aws_subnets.default.ids
    tags = {
        Name = "backend-alb"
    }
}

resource "aws_lb_target_group" "frontend_tg" {
    health_check {
        interval            = 10
        path                = "/"
        protocol            = "HTTP"
        timeout             = 5
        healthy_threshold   = 5
        unhealthy_threshold = 2
    }
    name          = "frontend-tg"
    port          = 8081
    protocol      = "HTTP"
    target_type   = "instance"
    vpc_id = data.aws_vpc.default.id
}

resource "aws_lb_target_group" "backend_tg" {
    health_check {
        interval            = 10
        path                = "/"
        protocol            = "HTTP"
        timeout             = 5
        healthy_threshold   = 5
        unhealthy_threshold = 2
    }
    name          = "backend-tg"
    port          = 8080
    protocol      = "HTTP"
    target_type   = "instance"
    vpc_id = data.aws_vpc.default.id
}

resource "aws_lb_listener" "frontend_listener" {
    load_balancer_arn          = aws_lb.frontend_alb.arn
    port                       = 80
    protocol                   = "HTTP"
    default_action {
        target_group_arn         = aws_lb_target_group.frontend_tg.arn
        type                     = "forward"
    }
}

resource "aws_lb_listener" "backend_listener" {
    load_balancer_arn          = aws_lb.backend_alb.arn
    port                       = 80
    protocol                   = "HTTP"
    default_action {
        target_group_arn         = aws_lb_target_group.backend_tg.arn
        type                     = "forward"
    }
}

resource "aws_lb_target_group_attachment" "frontend_attach" {
    count            = length(aws_instance.frontend)
    target_group_arn = aws_lb_target_group.frontend_tg.arn
    target_id        = aws_instance.frontend[count.index].id
}

resource "aws_lb_target_group_attachment" "backend_attach" {
    count            = length(aws_instance.backend)
    target_group_arn = aws_lb_target_group.backend_tg.arn
    target_id        = aws_instance.backend[count.index].id
}