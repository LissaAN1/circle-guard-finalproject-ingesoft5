# Módulo `network`

Crea la red de un ambiente de CircleGuard: VPC, subredes públicas en varias
zonas de disponibilidad, Internet Gateway, tabla de rutas y el security group
de los nodos del clúster.

## Variables

| Nombre | Tipo | Por defecto | Descripción |
|:---|:---|:---|:---|
| `name` | string | requerida | Prefijo de los recursos, por ejemplo `circleguard-dev`. |
| `environment` | string | requerida | `dev`, `stage` o `prod`. |
| `vpc_cidr` | string | `10.0.0.0/16` | CIDR de la VPC. |
| `public_subnet_cidrs` | list(string) | `["10.0.1.0/24","10.0.2.0/24"]` | Una subred por zona. |
| `availability_zones` | list(string) | `["us-east-1a","us-east-1b"]` | Zonas de las subredes. |
| `admin_cidrs` | list(string) | `[]` | IPs del operador para SSH y API de Kubernetes. No admite `0.0.0.0/0`. |
| `public_ingress_ports` | list(number) | `[80, 443]` | Puertos TCP públicos. |
| `tags` | map(string) | `{}` | Etiquetas adicionales. |

## Salidas

| Nombre | Descripción |
|:---|:---|
| `vpc_id` | ID de la VPC. |
| `public_subnet_ids` | IDs de las subredes públicas. |
| `cluster_security_group_id` | Security group para los nodos del clúster. |

## Ejemplo

```hcl
module "network" {
  source      = "../../modules/network"
  name        = "circleguard-dev"
  environment = "dev"
  admin_cidrs = ["203.0.113.10/32"]
}
```
