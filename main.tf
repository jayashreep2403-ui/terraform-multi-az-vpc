
locals {
  environment = "dev"
  project     = "portfolio-vpc"
  
  common_tags = {
    Environment = local.environment
    Project     = local.project
    ManagedBy   = "Terraform"
  }
}

data "aws_availability_zones" "available" { 
         state = "available" 
      }

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true 
  enable_dns_support   = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project}-${local.environment}-vpc"
    }
  )
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24" 
  availability_zone = data.aws_availability_zones.available.names[0] 
  
  
  map_public_ip_on_launch = true 

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-public-1"
  })
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1] 
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-public-2"
  })
}


resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-private-1"
  })
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-private-2"
  })
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-igw"
  })
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  
  route {
    cidr_block = "0.0.0.0/0" 
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-public-rt"
  })
}


resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}


resource "aws_eip" "nat" {
  domain = "vpc" 

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-nat-eip"
  })
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id 

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-nat-gw"
  })

 
  depends_on = [aws_internet_gateway.gw] 
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-private-rt"
  })
}


resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}


resource "aws_security_group" "web" {
  name        = "${local.project}-${local.environment}-web-sg"
  description = "Allow public web traffic"
  vpc_id      = aws_vpc.main.id

  
  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" 
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-web-sg"
  })
}

resource "aws_security_group" "db" {
  name        = "${local.project}-${local.environment}-db-sg"
  description = "Restricted database access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL/Aurora traffic ONLY from Web SG"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id] 
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-db-sg"
  })
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}


resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro" 

 
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web.id]

  
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello World from your Multi-AZ VPC!</h1>" > /var/www/html/index.index
              EOF

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-web-server"
  })
}


output "web_public_ip" {
  description = "The public IP address of our web server"
  value       = aws_instance.web_server.public_ip
}
