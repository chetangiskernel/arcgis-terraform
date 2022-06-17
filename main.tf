#crude approach
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
}

resource "aws_vpc" "ArcGIS_VPC" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "ArcGIS_VPC"
  }
}

resource "aws_subnet" "ArcGIS_subnet1" {
  vpc_id     = aws_vpc.ArcGIS_VPC.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "ArcGIS_subnet1"
  }
}

resource "aws_subnet" "ArcGIS_subnet2" {
  vpc_id     = aws_vpc.ArcGIS_VPC.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "ArcGIS_subnet2"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.ArcGIS_VPC.id

  tags = {
    Name = "gw"
  }
}

resource "aws_network_interface" "arcgis_p_ni" {
  subnet_id   = aws_subnet.ArcGIS_subnet1.id
  private_ips = ["10.0.1.100"]

  tags = {
    Name = "arcgis_p_ni"
  }
}

resource "aws_network_interface" "arcgis_s_ni" {
  subnet_id   = aws_subnet.ArcGIS_subnet1.id
  private_ips = ["10.0.1.101"]

  tags = {
    Name = "arcgis_s_ni"
  }
}

resource "aws_instance" "arcgis_server_p" {
  ami           = "ami-0c4f7023847b90238"
  instance_type = "t2.micro"

  network_interface {
    network_interface_id = aws_network_interface.arcgis_p_ni.id
    device_index         = 0
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install apache2 -y
              sudo systemctl start apache2
              sudo bash -c 'echo machine p > /var/www/html/index.html'
              EOF

  tags = {
    Name = "arcgis_server_p"
  }
}

resource "aws_instance" "arcgis_server_s" {
  ami           = "ami-0c4f7023847b90238"
  instance_type = "t2.micro"

  network_interface {
    network_interface_id = aws_network_interface.arcgis_s_ni.id
    device_index         = 0
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install apache2 -y
              sudo systemctl start apache2
              sudo bash -c 'echo machine s > /var/www/html/index.html'
              EOF

  tags = {
    Name = "arcgis_server_s"
  }
}

resource "aws_security_group" "arcgis_sg" {
  name        = "arcgis_sg"
  vpc_id      = aws_vpc.ArcGIS_VPC.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.ArcGIS_VPC.cidr_block]
    #ipv6_cidr_blocks = [aws_vpc.ArcGIS_VPC.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "arcgis_sg"
  }
}


resource "aws_lb_target_group" "tg1" {
  name     = "lb-tg1"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.ArcGIS_VPC.id
}

resource "aws_lb_target_group_attachment" "tg1_attach_p" {
  target_group_arn = aws_lb_target_group.tg1.arn
  target_id        = aws_instance.arcgis_server_p.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "tg1_attach_s" {
  target_group_arn = aws_lb_target_group.tg1.arn
  target_id        = aws_instance.arcgis_server_s.id
  port             = 80
}

resource "aws_lb" "arcgis-alb" {
  name               = "arcgis-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.arcgis_sg.id]
  subnets            = [aws_subnet.ArcGIS_subnet1.id, aws_subnet.ArcGIS_subnet2.id]

  enable_deletion_protection = false

  tags = {
    Environment = "dev"
  }
}

resource "aws_lb_listener" "arcgis_alb_lstnr" {
  load_balancer_arn = aws_lb.arcgis-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg1.arn
  }
}

