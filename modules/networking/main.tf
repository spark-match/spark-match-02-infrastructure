###############################################################################
# Module: networking
# Description: VPC con subnets publicas y privadas, Internet Gateway,
#              NAT Gateway y route tables para una region AWS.
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(
    var.tags,
    {
      Name = var.vpc_name
    },
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-igw"
    },
  )
}

# --- Subnets publicas (2 AZs) ---
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-public-${var.azs[count.index]}"
      Tier = "public"
    },
  )
}

# --- Subnets privadas (2 AZs) ---
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-private-${var.azs[count.index]}"
      Tier = "private"
    },
  )
}

# --- Elastic IP para NAT Gateway ---
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-nat-eip"
    },
  )
  depends_on = [aws_internet_gateway.main]
}

# --- NAT Gateway en la primera subnet publica ---
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-nat"
    },
  )
  depends_on = [aws_internet_gateway.main]
}

# --- Route table publica ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-public-rt"
    },
  )
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Route table privada (via NAT) ---
resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway ? 1 : 0
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }
  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-private-rt"
    },
  )
}

resource "aws_route_table_association" "private" {
  count          = var.enable_nat_gateway ? length(var.private_subnet_cidrs) : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}
