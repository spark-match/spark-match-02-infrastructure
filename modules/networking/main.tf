###############################################################################
# Module: networking
#
# Red productiva para Spark Match (Fase 1):
#   - VPC principal con DNS support + hostnames habilitados
#   - 2 AZs con subnets publicas + privadas cada una
#   - 1 Internet Gateway (compartido)
#   - NAT Gateway en 1 sola AZ (default; HA relax para ahorrar costo)
#   - Route tables separadas para public/private, con asociaciones por subnet
#   - VPC Endpoints interface (ssm, ssmmessages, ec2messages, secretsmanager,
#     kms, logs, ecr.api, ecr.dkr, bedrock-runtime, sts) y Gateway (s3)
#
# Decisiones de diseno (ver IAM_ROLES.md y DEPLOYMENT):
#   - HA NAT (1 por AZ) se activa con `enable_nat_ha = true`. Costo extra ~$35/mes
#     vs NAT unico. Recomendable solo en produccion.
#   - CIDR 10.0.0.0/16 /20 por subnet / 2 subnets / AZ = ~250 hosts por subnet.
#     Suficiente para Aurora (max 32 vCPUs en RDS subnet group), Bedrock
#     serverless (sin ENI), y Lambda ENIs.
#   - NO hay peering/transit gateway hasta que aparezca un segundo VPC.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "networking"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  # Numero de NAT Gateways (y por extension EIPs, private RTs, asociaciones):
  #   enable_nat_gateway=false                -> 0 (sin NAT, sin rutas privadas a internet)
  #   enable_nat_gateway=true,  enable_nat_ha=false -> 1 (NAT unico compartido, ahorra $32/mes)
  #   enable_nat_gateway=true,  enable_nat_ha=true  -> N (uno por AZ, HA real)
  nat_count = var.enable_nat_gateway ? (var.enable_nat_ha ? length(var.azs) : 1) : 0
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

###############################################################################
# Subnets
###############################################################################

# Subnets publicas (1 por AZ) - con auto public IP para NAT.
resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.main.id
  availability_zone       = var.azs[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-${var.azs[count.index]}"
    Tier = "public"
  })
}

# Subnets privadas (1 por AZ) - sin public IP, salida via NAT.
resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.private_subnet_cidrs[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-${var.azs[count.index]}"
    Tier = "private"
  })
}

###############################################################################
# Internet Gateway + Elastic IP (para NAT)
###############################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

# Elastic IPs para NAT (1 o N segun enable_nat_ha, controlado por local.nat_count).
resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip-${var.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

###############################################################################
# NAT Gateway(s)
###############################################################################

resource "aws_nat_gateway" "main" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-${var.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

###############################################################################
# Route tables
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route table privada:
#   - Sin NAT (nat_count=0): no se crea ninguna RT ni asociacion (dev offline).
#   - NAT sin HA (nat_count=1): 1 RT compartida, todas las subnets privadas la usan.
#   - NAT con HA (nat_count=N): N RTs (1 por AZ), cada subnet privada usa la de su AZ
#     para rutear al NAT local (mejor latencia y aislamiento).
resource "aws_route_table" "private" {
  count = local.nat_count

  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = local.nat_count > 0 ? [1] : []
    content {
      cidr_block = "0.0.0.0/0"
      # Si HA=true, cada RT rutea al NAT de su propia AZ (aws_nat_gateway.main[i]).
      # Si HA=false, todas las RTs (que en este caso es 1) rutean al mismo NAT (index 0).
      nat_gateway_id = var.enable_nat_ha ? aws_nat_gateway.main[count.index].id : aws_nat_gateway.main[0].id
    }
  }

  tags = merge(local.common_tags, {
    Name = local.nat_count > 1 ? "${var.project_name}-${var.environment}-private-rt-${var.azs[count.index]}" : "${var.project_name}-${var.environment}-private-rt"
  })

  depends_on = [aws_nat_gateway.main]
}

resource "aws_route_table_association" "private" {
  count = local.nat_count

  subnet_id = aws_subnet.private[count.index].id
  # Si HA=true, cada subnet usa la RT de su AZ (rt[i]).
  # Si HA=false, todas las subnets usan la unica RT (rt[0]).
  route_table_id = local.nat_count > 1 ? aws_route_table.private[count.index].id : aws_route_table.private[0].id
}
