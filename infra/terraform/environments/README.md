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

Aplicar crea recursos con costo en AWS (instancias EC2, volúmenes).

## Estado de la validación

En este avance, los ambientes se entregan definidos y validados mediante pruebas con proveedores simulados (`fmt`, `validate` y `terraform test`); **no se aplicó ninguno en AWS**. Su aplicación y verificación real en AWS se realizarán posteriormente, de acuerdo con HU-10 y HU-11, antes del cierre de la Parte 2: la Parte 2 exige los tres ambientes, así que `stage` y `prod` también hay que desplegarlos y verificarlos, no solo `dev`.

## Registro de imágenes: Nexus y ECR

**Nexus sigue siendo el registro principal de imágenes**: es el que usa Jenkins hoy, y **HU-13 seguirá usando Nexus mientras el equipo no acuerde una migración**. Cada ambiente aprovisiona un repositorio ECR por servicio (8 por ambiente, 24 en total al aplicar los tres) únicamente como parte del aprovisionamiento de TEC-09: son la pieza reutilizable de registro y **ningún pipeline publica en ECR todavía**, de modo que no hay dos fuentes de imágenes en uso. Si el equipo decide no usarlos, basta con quitar la llamada al módulo `registry` (y su salida y su prueba) de cada ambiente; ningún otro módulo depende de él. Si el equipo decide usar ECR más adelante, antes hay que acordar la promoción entre ambientes y la autenticación de Jenkins y de los nodos k3s; ambos puntos están descritos en el [README del módulo `registry`](../modules/registry/README.md#propósito-y-relación-con-nexus). Esta decisión queda por confirmar en el equipo antes de HU-13.

## Acceso de Jenkins a la API de Kubernetes (propuesta para HU-13)

Cada ambiente tiene su propia VPC (`10.0.0.0/16`, `10.1.0.0/16`, `10.2.0.0/16`), distinta de la red donde corre Jenkins, así que Jenkins no llega a la API de k3s (puerto 6443) por red privada: tener rangos distintos no conecta las VPC entre sí. Hay dos caminos razonables: acceder a cada API por su dirección pública restringida al origen de Jenkins, o establecer conectividad privada entre Jenkins y las VPC (mejor aislamiento, pero con infraestructura adicional). Este PR no implementa la integración, que corresponde también a HU-11 y HU-13; propone el mecanismo para acordarlo y no rediseñar después el despliegue desde Jenkins:

1. **Abrir 6443 solo a Jenkins.** Agregar la IP pública de Jenkins, como `/32`, a `admin_cidrs` de cada ambiente (en `terraform.tfvars`, que git ignora). Ninguna otra dirección llega a la API. Limitación actual: el módulo `network` abre con la misma lista el SSH (22) y la API (6443); separarlas es un cambio pequeño del módulo si se quiere dar a Jenkins solo la API.
2. **IP estable.** La IP pública de una instancia cambia al apagarla y encenderla; hay que asignar una Elastic IP a Jenkins o actualizar `admin_cidrs` cada vez, porque si no el acceso se rompe en silencio.
3. **Credencial de mínimo privilegio.** Jenkins no usa el kubeconfig de administrador: usa el token de una ServiceAccount limitada a los espacios de nombres de la aplicación (HU-11), guardado como credencial de Jenkins y distinta por ambiente.
4. **Alternativa más cerrada.** Emparejar la VPC de Jenkins con cada ambiente (VPC peering; los rangos no se solapan) y llegar por IP privada sin abrir 6443 a Internet. Requiere rutas y reglas de security group que el módulo `network` aún no tiene.

Se propone la opción 1 con 2 y 3 para HU-13 por ser la más simple, y dejar la opción 4 como endurecimiento. Falta acordarlo en el equipo.

## Pruebas

```bash
cd infra/terraform/environments/<ambiente>
terraform init -backend=false
terraform validate
terraform test   # proveedores simulados: no crea nada en AWS
```

Cada `tests/<ambiente>.tftest.hcl` comprueba que los módulos queden conectados con el nombre `circleguard-<ambiente>`, un repositorio y un grupo de logs por servicio, una alarma de CPU por cada nodo (servidor y agentes), el dimensionamiento propio del ambiente y que se rechace abrir la administración a todo internet.
