terraform {
  backend "s3" {
    bucket = "iis-backend-seyithan"
    key    = "terraform/terraform.tfstate"
    region = "eu-central-1"
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-central-1"
}

#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

locals {
  is_windows = substr(pathexpand("~"), 0, 1) == "/" ? false : true
  key_file   = pathexpand("MyAWSKey.pem")
}

locals {
  bash       = "chmod 400 ${local_file.private_key_pem.filename}"
  powershell = "icacls ${local_file.private_key_pem.filename} /inheritancelevel:r /grant:r Administrators:R"
}


#Define the VPC 
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = var.vpc_name
    Environment = "ec2-blue-green"
    Terraform   = "true"
  }

  enable_dns_hostnames = true
}

#Deploy the private subnets
resource "aws_subnet" "private_subnets" {
  for_each          = var.private_subnets
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone = tolist(data.aws_availability_zones.available.names)[each.value]

  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Deploy the public subnets
resource "aws_subnet" "public_subnets" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone       = tolist(data.aws_availability_zones.available.names)[each.value]
  map_public_ip_on_launch = true

  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Create route tables for public and private subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
    #nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "public_rtb"
    Terraform = "true"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    # gateway_id     = aws_internet_gateway.internet_gateway.id
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "private_rtb"
    Terraform = "true"
  }
}

#Create route table associations
resource "aws_route_table_association" "public" {
  depends_on     = [aws_subnet.public_subnets]
  route_table_id = aws_route_table.public_route_table.id
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
}

resource "aws_route_table_association" "private" {
  depends_on     = [aws_subnet.private_subnets]
  route_table_id = aws_route_table.private_route_table.id
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
}

#Create Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "my_igw"
  }
}

#Create EIP for NAT Gateway
resource "aws_eip" "nat_gateway_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name = "my_igw_eip"
  }
}

#Create NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on    = [aws_subnet.public_subnets]
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name = "my_nat_gateway"
  }
}


resource "random_string" "random" {
  length = 10
}

# Terraform Data Block - To Lookup Latest Windows Server 2022 AMI
data "aws_ami" "windows_server" {
  most_recent = true

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["801119661308"] # Microsoft's owner ID for Windows AMIs
}

resource "aws_s3_bucket_object" "setup_script" {
  bucket = "iis-backend-seyithan"  
  key    = "user-data.ps1"
  source = "${path.module}/../scripts/setup-script.ps1"
}
resource "aws_instance" "windows_server" {
  count                       = 2
  ami                         = data.aws_ami.windows_server.id
  instance_type               = "t3a.medium"
  #subnet_id                   = tolist(values(aws_subnet.private_subnets))[count.index % length(values(aws_subnet.private_subnets))].id
  subnet_id                   = tolist(values(aws_subnet.public_subnets))[count.index % length(values(aws_subnet.public_subnets))].id
  vpc_security_group_ids      = [aws_security_group.rdp.id, aws_security_group.iis_access.id]
  key_name                    = aws_key_pair.generated.key_name
  user_data                   = <<-EOF
    <powershell>
    Read-S3Object -BucketName ${aws_s3_bucket_object.setup_script.bucket} -Key ${aws_s3_bucket_object.setup_script.key} -File c:\devops\setup-script.ps1
    Start-Process "powershell.exe" -ArgumentList "-File c:\devops\setup-script.ps1" -Wait
    </powershell>
  EOF
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  
  metadata_options {
    http_tokens         = "required" 
    http_put_response_hop_limit = 2 
    http_endpoint       = "enabled" 
    instance_metadata_tags = "enabled"
  }

  tags = {
    Name = "${var.repo_name}-${count.index + 1}"
  }
}



# Terraform Resource Block - Security Group to Allow Ping Traffic
resource "aws_security_group" "vpc-ping" {
  name        = "vpc-ping"
  vpc_id      = aws_vpc.vpc.id
  description = "ICMP for Ping Access"
  ingress {
    description = "Allow ICMP Traffic"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all ip and ports outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
}

resource "local_file" "private_key_pem" {
  content  = tls_private_key.generated.private_key_pem
  filename = "MyAWSKey.pem"
}

resource "aws_key_pair" "generated" {
  key_name   = "MyAWSKey"
  public_key = tls_private_key.generated.public_key_openssh
}

# Create security groups for RDP, IIS (HTTP and HTTPS)
resource "aws_security_group" "rdp" {
  name   = "allow-rdp"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "Allow RDP access"
    from_port   = 3389
    to_port     = 3389
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

resource "aws_security_group" "iis_access" {
  name   = "iis-access"
  vpc_id = aws_vpc.vpc.id


  ingress {
    description      = "ALB to EC2"
    from_port        = var.iis_port
    to_port          = var.iis_port
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_sg.id] 
  }

  # Genel çıkış trafiğine izin ver
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_iam_role" "ec2_role" {
  name = "ec2_role_for_secrets_s3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "secrets_s3_ec2_access" {
  name        = "secrets_s3_ec2_access_policy"
  description = "Policy for EC2 to access Secret Manager, S3, EC2, and ELB with full access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:ListSecrets",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "ec2:*",
          "elasticloadbalancing:*" 
        ],
        Effect = "Allow",
        Resource = "*"
      },
    ]
  })
}


resource "aws_iam_role_policy_attachment" "attach_secrets_s3_ec2_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.secrets_s3_ec2_access.arn
}


resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "my_ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_lb" "main" {
  name               = "${var.repo_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = tolist([for subnet in aws_subnet.public_subnets : subnet.id])

  tags = {
    Name = "${var.repo_name}-lb"
  }
}


resource "aws_lb_target_group" "blue" {
  name     = "${var.repo_name}-main-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  deregistration_delay = 30

  tags = {
    Name = "${var.repo_name}-main-tg"
  }
}

resource "aws_lb_target_group_attachment" "attach_blue" {
  count            = length(aws_instance.windows_server.*.id)
  target_group_arn = aws_lb_target_group.blue.arn
  target_id        = aws_instance.windows_server[count.index].id
  port             = var.iis_port
}


resource "aws_lb_target_group" "green" {
  name     = "${var.repo_name}-deploy-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  deregistration_delay = 30

  tags = {
    Name = "${var.repo_name}-deploy-tg"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Bu sayfa kullanılamıyor."
      status_code  = "503"
    }
}
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Service is temporarily unavailable."
      status_code  = "503"
    }
  }
}
resource "aws_lb_listener_rule" "redirect_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type = "redirect"
    redirect {
      protocol   = "HTTPS"
      port       = "443"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = ["${var.repo_name}.${var.domain_name}"]
    }
  }
}


resource "aws_lb_listener_rule" "host_based_routing_blue_green" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = 100
      }

      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = 0
      }

      stickiness {
        enabled  = false
        duration = 600
      }
    }
  }

  condition {
    host_header {
      values = ["${var.repo_name}.${var.domain_name}"]
    }
  }
}


resource "aws_security_group" "alb_sg" {
  name   = "${var.repo_name}-alb-sg"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound HTTP traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound HTTPS traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}

resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "seyithan-${var.repo_name}-deploy"
  
  tags = {
    Name = "Seyithan IIS Bucket for ${var.repo_name}"
  }
}

resource "aws_secretsmanager_secret" "repo_secret" {
  name = "iis-demo-${var.repo_name}"
  
}

resource "aws_secretsmanager_secret_version" "repo_secret_values" {
  secret_id     = aws_secretsmanager_secret.repo_secret.id
  secret_string = jsonencode({
    "seyithan_pfx"           = var.seyithan_pfx,
    "seyithan_pfx_secret"    = var.seyithan_pfx_secret,
    "gh_action_token"        = var.gh_action_token
  })
}

output "secret_arn" {
  description = "The ARN of the AWS Secrets Manager secret"
  value       = aws_secretsmanager_secret.repo_secret.arn
}

output "green_target_group_arn" {
  value = aws_lb_target_group.green.arn
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "blue_green_listener_rule_arn" {
  value = aws_lb_listener_rule.host_based_routing_blue_green.arn
}
