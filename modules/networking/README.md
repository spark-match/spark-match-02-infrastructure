# Module: networking

VPC con subnets p\'ublicas/privadas en 2 AZs, Internet Gateway y NAT Gateway opcional.

## Recursos creados

- `aws_vpc`
- `aws_internet_gateway`
- `aws_subnet` (publicas y privadas)
- `aws_eip` + `aws_nat_gateway` (condicional)
- `aws_route_table` + `aws_route_table_association`

## Uso

```hcl
module "networking" {
  source = "../../modules/networking"

  vpc_name             = "spark-match-prod"
  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  enable_nat_gateway   = true

  tags = {
    Project     = "spark-match"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
```

## Outputs

| Output | Descripci\'on |
|---|---|
| `vpc_id` | ID de la VPC |
| `vpc_cidr_block` | CIDR principal |
| `public_subnet_ids` | IDs de subnets p\'ublicas |
| `private_subnet_ids` | IDs de subnets privadas |
| `nat_gateway_id` | ID del NAT (null si desactivado) |
| `internet_gateway_id` | ID del IGW |