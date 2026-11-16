# Módulo `observability`

Crea la base de logs y alertas de un ambiente en **Amazon CloudWatch**:

- Un grupo de logs por servicio (`/<name>/<servicio>`) con retención acotada, para que los logs no crezcan sin límite.
- Un tema **SNS** (`<name>-alarms`) que recibe las notificaciones de las alarmas.
- Una alarma de CPU alta por cada instancia EC2 indicada (promedio sobre el umbral durante 10 minutos). Avisa también cuando vuelve a la normalidad.
- Opcionalmente, una suscripción por correo al tema. Si `alarm_email` queda vacío no se suscribe a nadie.

El módulo no crea usuarios, roles ni agentes de recolección. Quien envíe logs a los grupos (por ejemplo los nodos k3s) necesita permisos aparte.

## Variables

| Nombre | Tipo | Por defecto | Descripción |
|:---|:---|:---|:---|
| `name` | string | requerida | Prefijo de los recursos, por ejemplo `circleguard-dev`. |
| `environment` | string | requerida | `dev`, `stage` o `prod`. |
| `services` | list(string) | requerida | Servicios que reciben un grupo de logs. Al menos uno, sin repetidos, en minúsculas. |
| `log_retention_days` | number | `30` | Días de retención. Debe ser un valor que CloudWatch acepte (7, 14, 30, 90, 365, ...). |
| `instance_ids` | list(string) | `[]` | Instancias EC2 con alarma de CPU alta. |
| `cpu_alarm_threshold` | number | `80` | Porcentaje medio de CPU que dispara la alarma (1 a 100). |
| `alarm_email` | string | `""` | Correo suscrito al tema de alarmas. Vacío = sin suscripción. |
| `tags` | map(string) | `{}` | Etiquetas adicionales. |

## Requisitos

Terraform `>= 1.9.0` y provider `hashicorp/aws ~> 5.0`.

## Salidas

| Nombre | Descripción |
|:---|:---|
| `log_group_names` | Mapa servicio → nombre del grupo de logs. |
| `alarm_topic_arn` | ARN del tema SNS de alarmas. |
| `cpu_alarm_names` | Nombres de las alarmas de CPU. |

## Ejemplo

```hcl
module "observability" {
  source       = "../../modules/observability"
  name         = "circleguard-dev"
  environment  = "dev"
  services     = ["auth-service", "gateway-service"]
  instance_ids = [module.compute.server_instance_id]
}
```

## Pruebas

```bash
terraform init -backend=false
terraform validate
terraform test   # usa un provider simulado: no crea nada en AWS
```

`tests/observability.tftest.hcl` comprueba un grupo de logs por servicio con retención de 30 días, que no haya alarmas ni suscripción por defecto, la alarma por instancia con su umbral, la suscripción por correo y que se rechacen servicios vacíos o repetidos, una retención no válida, un umbral fuera de rango, un correo mal formado y un ambiente desconocido.
