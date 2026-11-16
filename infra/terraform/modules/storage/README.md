# Módulo `storage`

Crea un bucket **Amazon S3** privado para un ambiente, pensado para artefactos
o reportes de CircleGuard. El nombre es `<name>-<purpose>-<id de cuenta>`, de
modo que es único a nivel global sin escribir identificadores a mano.

- Acceso público bloqueado por completo y propiedad de objetos forzada al dueño del bucket.
- Cifrado en reposo (AES256).
- Solo se aceptan conexiones con TLS: una política rechaza cualquier petición sin HTTPS.
- Versionado activado por defecto; las versiones anteriores caducan a los `noncurrent_version_expiration_days` días y las cargas multiparte incompletas a los 7.

El módulo no crea usuarios ni llaves de acceso. Quien necesite leer o escribir en
el bucket (por ejemplo un rol IAM) recibe permisos aparte, usando `bucket_arn`.

## Variables

| Nombre | Tipo | Por defecto | Descripción |
|:---|:---|:---|:---|
| `name` | string | requerida | Prefijo del bucket, por ejemplo `circleguard-dev`. |
| `environment` | string | requerida | `dev`, `stage` o `prod`. |
| `purpose` | string | `artifacts` | Qué guarda el bucket; entra en el nombre. Minúsculas, dígitos y guiones. |
| `versioning_enabled` | bool | `true` | Conservar versiones anteriores de cada objeto. |
| `noncurrent_version_expiration_days` | number | `30` | Días tras los cuales se borran las versiones anteriores (entero, mínimo 1). |
| `force_destroy` | bool | `false` | Permite destruir el bucket con objetos dentro. Solo se acepta con `environment = "dev"`. |
| `tags` | map(string) | `{}` | Etiquetas adicionales. |

## Requisitos

Terraform `>= 1.9.0` y provider `hashicorp/aws ~> 5.0`.

## Salidas

| Nombre | Descripción |
|:---|:---|
| `bucket_name` | Nombre del bucket. |
| `bucket_arn` | ARN del bucket. |

## Ejemplo

```hcl
module "reports" {
  source      = "../../modules/storage"
  name        = "circleguard-dev"
  environment = "dev"
  purpose     = "reports"
}
```

## Pruebas

```bash
terraform init -backend=false
terraform validate
terraform test   # usa un provider simulado: no crea nada en AWS
```

`tests/storage.tftest.hcl` comprueba los valores seguros por defecto (acceso público bloqueado, versionado, cifrado, nombre con id de cuenta) y que se rechacen `force_destroy` fuera de dev, un `purpose` inválido, una caducidad de 0 o fraccionaria y un ambiente desconocido.
