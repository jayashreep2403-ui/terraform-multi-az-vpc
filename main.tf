# Local values to keep our tagging standardized and reusable
locals {
  environment = "dev"
  project     = "portfolio-vpc"
  
  common_tags = {
    Environment = local.environment
    Project     = local.project
    ManagedBy   = "Terraform"
  }
}
#for multi-Az fetching data centres dynamically jo availiable ho------
data "aws_availability_zones" "available" { 
         state = "available" 
      }
#made vpc  ------------------------------------------------------------------------------------------------------
# The core VPC configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true # Gives our EC2 instances readable domain names instead of just raw numbers
  enable_dns_support   = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project}-${local.environment}-vpc"
    }
  )
}
# 4 subnets creation --------------------------------------------------------------------------------------------
# --- PUBLIC SUBNETS ---
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24" # 256 IP addresses
  availability_zone = data.aws_availability_zones.available.names[0] # Dynamic AZ 1
  
  # Crucial: This ensures any server launched here gets a public IP address automatically
  map_public_ip_on_launch = true 

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-public-1"
  })
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1] # Dynamic AZ 2
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-public-2"
  })
}

# --- PRIVATE SUBNETS ---
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

#-----yaha humne Public subnet ke liye IGW aur route table banaya-----------------------------------------------------
# --- INTERNET GATEWAY ---
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-igw"
  })
}

# --- PUBLIC ROUTE TABLE ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # The explicit roadmap rule out to the internet
  route {
    cidr_block = "0.0.0.0/0" # Represents all IP addresses on the internet
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-public-rt"
  })
}

# --- ROUTE TABLE ASSOCIATIONS ---
# Link our Public Route Table to Public Subnet 1
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# Link our Public Route Table to Public Subnet 2
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

#-----yaha humne private subnet ke liye NAT gateway aur route table banaya------------------------------------------
# --- ELASTIC IP FOR NAT ---
resource "aws_eip" "nat" {
  domain = "vpc" # Tells AWS this IP is for use inside a VPC

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-nat-eip"
  })
}

# --- NAT GATEWAY ---
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id # Must be placed in a PUBLIC subnet

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-nat-gw"
  })

  # Expert tip: Enforces Terraform to finish building the Internet Gateway first
  depends_on = [aws_internet_gateway.gw] 
}

# --- PRIVATE ROUTE TABLE ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Route private traffic through the NAT Gateway
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-private-rt"
  })
}

# --- PRIVATE ROUTE TABLE ASSOCIATIONS ---
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

#hum security group add kar rahe hai abh --------------------------------------------------------------------
# --- WEB TIER SECURITY GROUP ---
resource "aws_security_group" "web" {
  name        = "${local.project}-${local.environment}-web-sg"
  description = "Allow public web traffic"
  vpc_id      = aws_vpc.main.id

  # Ingress = Incoming traffic rules
  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # The public internet
  }

  # Egress = Outgoing traffic rules
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # "-1" means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-web-sg"
  })
}

# --- DATABASE TIER SECURITY GROUP ---
resource "aws_security_group" "db" {
  name        = "${local.project}-${local.environment}-db-sg"
  description = "Restricted database access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL/Aurora traffic ONLY from Web SG"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    # PRO TIP: Chaining the security group instead of typing IP address blocks
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
# EC2 instance bana liya ---------------------------------------------------------------------------------
# --- DYNAMIC AMI LOOKUP ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"] # Finds the official Amazon Linux 2023 image
  }
}

# --- VALIDATION EC2 INSTANCE ---
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro" # Free-tier eligible compute size

  # Place it into our Public Subnet
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web.id]

  # A basic startup script to install a web server and say hello
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

# --- OUTPUT THE PUBLIC IP ---
output "web_public_ip" {
  description = "The public IP address of our web server"
  value       = aws_instance.web_server.public_ip
}
