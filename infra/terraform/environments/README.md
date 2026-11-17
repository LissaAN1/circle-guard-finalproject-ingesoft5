# Ambientes `dev`, `stage` y `prod`

Cada carpeta es una configuración raíz independiente que arma el ambiente completo con los cinco módulos de [`../modules`](../README.md): red, clúster k3s, repositorios ECR, bucket de artefactos y observabilidad (logs y alarmas). Cada ambiente guarda su estado en el backend remoto que crea [`../bootstrap`](../bootstrap/README.md), con su propia llave, de modo que los estados no se mezclan.

| | `dev` | `stage` | `prod` |
|:---|:---|:---|:---|
| Red (VPC) | `10.0.0.0/16` | `10.1.0.0/16` | `10.2.0.0/16` |
| Nodos k3s | 1 servidor | 1 servidor + 1 agente | 1 servidor + 2 agentes |
| Disco por nodo | 30 GB | 30 GB | 50 GB |
| Retención de logs | 7 días | 30 días | 90 días |
| Borrado forzado de repositorios y bucket | sí | no | no |
| Llave del estado | `dev/terraform.tfstate` | `stage/terraform.tfstate` | `prod/terraform.tfstate` |

Los rangos de red no se solapan, así que los ambientes se pueden conectar entre sí más adelante si hace falta. Las diferencias de tamaño están en los valores por defecto de `variables.tf` de cada ambiente; el resto del código es el mismo.

## Archivos de cada ambiente

| Archivo | Para qué |
|:---|:---|
| `versions.tf` | Versiones de Terraform y proveedores, y `backend "s3" {}` (configuración parcial). |
| `variables.tf` | Dimensionamiento del ambiente (valores por defecto) y datos de la cuenta. |
| `main.tf` | Proveedor AWS con etiquetas por defecto y la llamada a los cinco módulos. |
| `outputs.tf` | IP del servidor, URLs de ECR, bucket, grupos de logs y tema de alarmas. |
| `backend.hcl.example` | Plantilla con el bucket, la tabla de bloqueo y la llave del ambiente. |
| `terraform.tfvars.example` | Plantilla de los valores propios de tu cuenta (IPs de administración, llave SSH, correo). |
| `tests/<ambiente>.tftest.hcl` | Pruebas de plan con proveedores simulados. |

El repositorio no guarda datos de la cuenta: `backend.hcl` y `terraform.tfvars` los ignora git. Las IPs de administración (`admin_cidrs`) no pueden ser `0.0.0.0/0`.

## Uso

Primero se crea el backend una sola vez (ver el README de `bootstrap`). Luego, para un ambiente:

```bash
cd infra/terraform/environments/dev
cp backend.hcl.example backend.hcl            # completa bucket y tabla con la salida del bootstrap
cp terraform.tfvars.example terraform.tfvars  # completa tus IPs de administración
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Aplicar crea recursos con costo en AWS (instancias EC2, volúmenes). Los ambientes `stage` y `prod` quedan definidos y validados, pero no hace falta aplicarlos para esta entrega.

## Pruebas

```bash
cd infra/terraform/environments/<ambiente>
terraform init -backend=false
terraform validate
terraform test   # proveedores simulados: no crea nada en AWS
```

Cada `tests/<ambiente>.tftest.hcl` comprueba que los módulos queden conectados con el nombre `circleguard-<ambiente>`, un repositorio y un grupo de logs por servicio, una alarma de CPU por cada nodo (servidor y agentes), el dimensionamiento propio del ambiente y que se rechace abrir la administración a todo internet.
