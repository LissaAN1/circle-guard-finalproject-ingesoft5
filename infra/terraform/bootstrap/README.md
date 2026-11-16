# Backend remoto del estado (`bootstrap`)

Crea lo necesario para que los ambientes (dev, stage, prod) guarden su estado de Terraform en AWS en lugar de en el equipo de cada persona:

- Un **bucket S3** `<name>-tfstate-<id de cuenta>`, creado con el módulo [`storage`](../modules/storage/README.md): privado, cifrado, solo TLS y versionado. Las versiones anteriores del estado se conservan 90 días para poder deshacer un `apply` equivocado.
- Una **tabla DynamoDB** `<name>-tfstate-lock` (on-demand, llave `LockID`, con recuperación a un punto en el tiempo y protección contra borrado). Terraform toma un bloqueo en ella durante `plan` y `apply`, así dos personas o dos ejecuciones del pipeline no cambian el mismo ambiente a la vez.

Cada ambiente usa una `key` distinta dentro del mismo bucket (`dev/terraform.tfstate`, `stage/terraform.tfstate`, `prod/terraform.tfstate`), de modo que sus estados no se mezclan.

## Por qué esta carpeta usa estado local

Un ambiente no puede guardar su estado en un bucket que todavía no existe. Por eso esta configuración se aplica **una sola vez**, con estado local, antes de cualquier ambiente. Después casi no cambia. Su estado local (`terraform.tfstate`) no se versiona: el `.gitignore` lo excluye. Guárdalo con quien aplicó el bootstrap o impórtalo después con `terraform import` si hace falta.

## Variables

| Nombre | Tipo | Por defecto | Descripción |
|:---|:---|:---|:---|
| `region` | string | `us-east-1` | Región del bucket y de la tabla. |
| `name` | string | `circleguard` | Prefijo del bucket y de la tabla. |
| `lock_table_deletion_protection` | bool | `true` | Protege la tabla de bloqueo contra borrado accidental. |
| `tags` | map(string) | `{}` | Etiquetas adicionales. |

## Salidas

| Nombre | Descripción |
|:---|:---|
| `state_bucket_name` | Bucket del estado. |
| `lock_table_name` | Tabla DynamoDB de bloqueo. |
| `region` | Región del backend. |
| `backend_config` | Valores listos para pegar en `backend.hcl` de cada ambiente. |

## Uso

```bash
cd infra/terraform/bootstrap
terraform init
terraform apply          # crea el bucket y la tabla (requiere credenciales AWS)
terraform output -raw backend_config
```

Luego, en cada ambiente, `terraform init -backend-config=backend.hcl` con esos valores y la `key` del ambiente (ver el README de `environments/`).

## Pruebas

```bash
terraform init -backend=false
terraform validate
terraform test   # usa un provider simulado: no crea nada en AWS
```

`tests/bootstrap.tftest.hcl` comprueba la llave `LockID`, el modo on-demand, la protección contra borrado y que `backend_config` apunte a la tabla y active el cifrado.
