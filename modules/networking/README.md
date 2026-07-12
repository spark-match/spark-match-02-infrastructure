# Module: `networking`

Red productiva para Spark Match (Fase 1).

## Recursos que crea

| Recurso | Cantidad | Notas |
|---|---|---|
| `aws_vpc` | 1 | DNS support + hostnames habilitados |
| `aws_subnet` public | N = `length(azs)` | `map_public_ip_on_launch = true` |
| `aws_subnet` private | N = `length(azs)` | Sin public IP, salida via NAT |
| `aws_internet_gateway` | 1 | Shared |
| `aws_eip` + `aws_nat_gateway` | 1 o N | Si `enable_nat_ha=true`, 1 por AZ. Si no, 1 sola en primera subnet publica |
| `aws_route_table` | 1 publica + 1 o N privadas | Privadas: 1 sola si HA off, 1 por AZ si HA on |
| `aws_route_table_association` | N per table | Subnets associate to the right RT |

## Decisiones de diseno

### NAT Gateway
- **Default (`enable_nat_ha=false`):** 1 NAT compartido en primera subnet publica. 
  Costo: $0.045/hora ~ $32/mes + data transfer. Suficiente para dev/staging/TFP.
- **HA (`enable_nat_ha=true`):** 1 NAT por AZ. Costo: $64/mes + transferencia.
  Cada subnet privada rutea al NAT de su misma AZ (latencia + aislamiento).
  Recomendable para produccion con SLO estricto.

### CIDR planning (default)
- VPC: `10.0.0.0/16` (65k IPs)
- Public subnets: `10.0.1.0/24`, `10.0.2.0/24` (~250 hosts c/u, mas que suficiente para NAT ENI)
- Private subnets: `10.0.10.0/24`, `10.0.11.0/24` (~250 hosts c/u para Aurora ENIs + Lambda ENIs + Bedrock MicroVMs)
- Libre para crecer a `/22` o `/21` por subnet si se necesita mas densidad.

### Endpoints
Este modulo NO crea los VPC endpoints. Los endpoints viven en `modules/endpoints`
porque su SG source viene de `modules/security`. Wiring tipico:

```hcl
module "networking" { ... }
module "security" {
  vpc_id = module.networking.vpc_id
  vpc_cidr = module.networking.vpc_cidr_block
  ...
}
module "endpoints" {
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  endpoints_security_group_id = module.security.sg_endpoints_id
  ...
}
```

## Outputs clave

- `vpc_id`, `vpc_cidr_block`
- `public_subnet_ids`, `private_subnet_ids`
- `public_route_table_id`, `private_route_table_ids`
- `nat_gateway_ids`
- `internet_gateway_id`

Ver `outputs.tf` para la lista completa.

## Wiring esperado

```hcl
module "networking" {
  source = "../modules/networking"

  project_name = "spark-match"
  environment  = "prod"
  aws_region   = "us-east-1"

  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  enable_nat_ha      = false  # true en prod si se quiere HA
  tags = local.common_tags
}
```

(Esto NO está aplicado aun; queda propuesto para el PR de Fase 1.)
