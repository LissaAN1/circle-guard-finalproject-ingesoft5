# Módulo `compute`

Crea los nodos del clúster **k3s sobre EC2** de un ambiente: un nodo servidor y,
opcionalmente, nodos agentes. Pensado para usarse con la salida del módulo
`network`.

- El token para unir nodos al clúster se genera con Terraform y se guarda en
  **SSM Parameter Store** (SecureString). Los nodos lo leen al arrancar con un
  rol IAM de solo lectura sobre ese parámetro; nunca aparece en el repositorio.
- Volúmenes cifrados (gp3) e IMDSv2 obligatorio.
- AMI: Ubuntu Server 24.04 LTS, resuelta desde el parámetro público de SSM.
- k3s incluye Traefik como Ingress controller, que se usará en HU-12.

## Variables

| Nombre | Tipo | Por defecto | Descripción |
|:---|:---|:---|:---|
| `name` | string | requerida | Prefijo de los recursos, por ejemplo `circleguard-dev`. |
| `environment` | string | requerida | `dev`, `stage` o `prod`. |
| `subnet_ids` | list(string) | requerida | Subredes de los nodos (salida `public_subnet_ids` de `network`). Al menos una. |
| `security_group_id` | string | requerida | Security group de los nodos (salida `cluster_security_group_id` de `network`). |
| `instance_type` | string | `m7i-flex.large` | Tipo de instancia de los nodos. |
| `root_volume_gb` | number | `30` | Tamaño del disco raíz en GB (mínimo 20). |
| `agent_count` | number | `0` | Nodos agentes además del servidor (0 a 10). |
| `k3s_version` | string | `v1.31.4+k3s1` | Versión de k3s, con formato `vX.Y.Z+k3sN`. |
| `ami_id` | string | `null` | AMI de los nodos; si es `null` se usa Ubuntu 24.04 LTS. |
| `key_name` | string | `null` | Key pair existente para SSH; `null` desactiva el acceso por llave. |
| `tags` | map(string) | `{}` | Etiquetas adicionales. |

## Requisitos

Terraform `>= 1.9.0`, providers `hashicorp/aws ~> 5.0` y `hashicorp/random ~> 3.6`.

## Salidas

| Nombre | Descripción |
|:---|:---|
| `server_instance_id` | ID de la instancia servidor. |
| `server_private_ip` | IP privada del servidor. |
| `server_public_ip` | IP pública del servidor (API de Kubernetes y entrada del Ingress). |
| `agent_instance_ids` | IDs de las instancias agentes. |
| `k3s_token_parameter_name` | Nombre del parámetro SSM con el token (el valor no se expone). |

## Ejemplo

```hcl
module "compute" {
  source            = "../../modules/compute"
  name              = "circleguard-dev"
  environment       = "dev"
  subnet_ids        = module.network.public_subnet_ids
  security_group_id = module.network.cluster_security_group_id
}
```

## Pruebas

```bash
terraform init -backend=false
terraform validate
terraform test   # usa providers simulados: no crea nada en AWS
```

`tests/compute.tftest.hcl` comprueba los valores por defecto (un solo servidor, disco cifrado, IMDSv2) y que se rechacen un ambiente desconocido, subredes vacías, discos menores de 20 GB, `agent_count` fuera de rango y versiones de k3s mal formadas.
