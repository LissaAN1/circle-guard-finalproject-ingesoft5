# Módulo `observability`

Crea la base de logs y alertas de un ambiente en **Amazon CloudWatch**:

- Un grupo de logs por servicio (`/<name>/<servicio>`) con retención acotada, para que los logs no crezcan sin límite.
- Un tema **SNS** (`<name>-alarms`) que recibe las notificaciones de las alarmas.
- Una alarma de CPU alta por cada instancia EC2 indicada (promedio sobre el umbral durante 10 minutos). Avisa también cuando vuelve a la normalidad.
- Opcionalmente, una suscripción por correo al tema. Si `alarm_email` queda vacío no se suscribe a nadie. La suscripción queda **pendiente** hasta que la persona confirme desde el correo que envía AWS; mientras tanto no recibe alertas.
- Opcionalmente, cifrado con una llave KMS propia (`kms_key_arn`) para el tema y los grupos de logs.

## Alcance

Este módulo es la base de infraestructura de la TEC-09 (módulos Terraform reutilizables). **No** es la observabilidad de la aplicación: nada envía todavía logs a estos grupos, y el módulo no sustituye la centralización de logs con Loki (HU-18) ni las alertas con Prometheus y Alertmanager (HU-17), que no deben tomarse como cubiertas por él.

El módulo no crea usuarios, roles ni agentes de recolección. Quien envíe logs a los grupos (por ejemplo los nodos k3s) necesita permisos aparte.

## Cifrado

Por defecto el tema SNS y los grupos de logs no usan una llave KMS propia (cifrado de servicio). Para cifrarlos pasa `kms_key_arn` con una llave administrada por el cliente cuya política permita a `cloudwatch.amazonaws.com` (publicar en el tema) y al servicio de logs usarla. No sirve la llave administrada `alias/aws/sns`: CloudWatch no puede publicar alarmas en un tema cifrado con ella.

## Variables

| Nombre | Tipo | Por defecto | Descripción |
|:---|:---|:---|:---|
| `name` | string | requerida | Prefijo de los recursos, por ejemplo `circleguard-dev`. |
| `environment` | string | requerida | `dev`, `stage` o `prod`. |
| `services` | list(string) | requerida | Servicios que reciben un grupo de logs. Al menos uno, sin repetidos, en minúsculas. |
| `log_retention_days` | number | `30` | Días de retención. Debe ser un valor que CloudWatch acepte (7, 14, 30, 90, 365, ...). |
| `instances` | map(string) | `{}` | Instancias EC2 con alarma de CPU alta: etiqueta estática → id de instancia. Las etiquetas deben conocerse en el plan; los ids pueden calcularse al aplicar. |
| `cpu_alarm_threshold` | number | `80` | Porcentaje medio de CPU que dispara la alarma (de 1 a 100). |
| `kms_key_arn` | string | `null` | Llave KMS propia para cifrar el tema SNS y los grupos de logs. Nulo = sin llave propia. |
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
  instances    = { server = module.compute.server_instance_id }
}
```

## Pruebas

```bash
terraform init -backend=false
terraform validate
terraform test   # usa un provider simulado: no crea nada en AWS
```

`tests/observability.tftest.hcl` comprueba un grupo de logs por servicio con retención de 30 días, que no haya alarmas ni suscripción por defecto, la alarma por instancia con su umbral, que el plan funcione cuando el id de la instancia solo se conoce al aplicar (`tests/with_computed_instance` la conecta como lo haría un ambiente), el cifrado con KMS, la suscripción por correo y que se rechacen servicios vacíos o repetidos, una retención no válida, un umbral fuera de rango o menor que 1, un correo mal formado y un ambiente desconocido.
