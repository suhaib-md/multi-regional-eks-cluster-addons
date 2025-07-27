# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-vpc-${var.region}"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}-${var.region}" = "shared"
  })
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-igw-${var.region}"
  })
}

# Create public subnets
resource "aws_subnet" "public" {
  count = min(length(data.aws_availability_zones.available.names), 3)
  
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-public-${count.index + 1}-${var.region}"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}-${var.region}" = "shared"
    "kubernetes.io/role/elb" = "1"
  })
}

# Create private subnets
resource "aws_subnet" "private" {
  count = min(length(data.aws_availability_zones.available.names), 3)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-private-${count.index + 1}-${var.region}"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}-${var.region}" = "owned"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# Create Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = min(length(data.aws_availability_zones.available.names), 3)
  
  domain = "vpc"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-eip-${count.index + 1}-${var.region}"
  })
  
  depends_on = [aws_internet_gateway.main]
}

# Create NAT Gateways
resource "aws_nat_gateway" "main" {
  count = min(length(data.aws_availability_zones.available.names), 3)
  
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}-${var.region}"
  })
  
  depends_on = [aws_internet_gateway.main]
}

# Create route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-public-rt-${var.region}"
  })
}

# Create route tables for private subnets
resource "aws_route_table" "private" {
  count = min(length(data.aws_availability_zones.available.names), 3)
  
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}-${var.region}"
  })
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = min(length(data.aws_availability_zones.available.names), 3)
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate private subnets with private route tables
resource "aws_route_table_association" "private" {
  count = min(length(data.aws_availability_zones.available.names), 3)
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}