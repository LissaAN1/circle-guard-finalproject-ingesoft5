# Backend remoto del estado (`bootstrap`)

Crea lo necesario para que los ambientes (dev, stage, prod) guarden su estado de Terraform en AWS en lugar de en el equipo de cada persona:

- Un **bucket S3** `<name>-tfstate-<id de cuenta>`, creado con el módulo [`storage`](../modules/storage/README.md): privado, cifrado, solo TLS y versionado. Las versiones anteriores del estado se conservan 90 días para poder deshacer un `apply` equivocado.
- Una **tabla DynamoDB** `<name>-tfstate-lock` (on-demand, llave `LockID`, con recuperación a un punto en el tiempo y protección contra borrado). Terraform toma un bloqueo en ella durante `plan` y `apply`, así dos personas o dos ejecuciones del pipeline no cambian el mismo ambiente a la vez.

Cada ambiente usa una `key` distinta dentro del mismo bucket (`dev/terraform.tfstate`, `stage/terraform.tfstate`, `prod/terraform.tfstate`), de modo que sus estados no se mezclan.

## Quién custodia el estado del bootstrap

Un ambiente no puede guardar su estado en un bucket que todavía no existe. Por eso el **primer** `apply` de esta carpeta usa estado local. Para que nadie tenga que custodiar ese archivo, el procedimiento termina **migrando el estado del propio bootstrap al bucket que acaba de crear**:

1. Quien aplica (con las credenciales AWS de la cuenta del proyecto) ejecuta `terraform init` y `terraform apply`. Aparece un `terraform.tfstate` local; el `.gitignore` lo excluye y no debe copiarse ni enviarse por ningún canal.
2. En seguida, en la misma sesión, se migra:
   ```bash
   cp backend.tf.example backend.tf
   terraform init -migrate-state \
     -backend-config="bucket=$(terraform output -raw state_bucket_name)" \
     -backend-config="dynamodb_table=$(terraform output -raw lock_table_name)"
   ```
   Responde `yes` a la pregunta de copiar el estado. El estado queda en `s3://<bucket>/bootstrap/terraform.tfstate`, cifrado, versionado y con bloqueo en DynamoDB.
3. Se borran los archivos locales: `rm terraform.tfstate terraform.tfstate.backup`. `backend.tf` también queda fuera de git (el `.gitignore` lo excluye), de modo que el primer `apply` en una cuenta nueva siga funcionando sin él.

**Dónde vive el estado y quién puede recuperarlo.** Después del paso 2 el único estado válido está en el bucket. Cualquier integrante con credenciales de la cuenta puede recuperarlo repitiendo `cp backend.tf.example backend.tf` y `terraform init -backend-config=...` (con el nombre del bucket y de la tabla, que no son secretos y se ven en la consola de AWS). Las versiones anteriores se conservan 90 días, así que un estado dañado se restaura desde el historial de versiones del objeto `bootstrap/terraform.tfstate`.

**Si el estado se pierde antes de migrarlo** (se borró el archivo local en el paso 1), no se pierde infraestructura: se vuelve a `terraform init` y se importan los recursos existentes, y el siguiente `plan` debe salir sin cambios:

```bash
terraform import 'module.state_bucket.aws_s3_bucket.this' <state_bucket_name>
terraform import 'module.state_bucket.aws_s3_bucket_public_access_block.this' <state_bucket_name>
terraform import 'module.state_bucket.aws_s3_bucket_ownership_controls.this' <state_bucket_name>
terraform import 'module.state_bucket.aws_s3_bucket_server_side_encryption_configuration.this' <state_bucket_name>
terraform import 'module.state_bucket.aws_s3_bucket_versioning.this' <state_bucket_name>
terraform import 'module.state_bucket.aws_s3_bucket_lifecycle_configuration.this' <state_bucket_name>
terraform import 'module.state_bucket.aws_s3_bucket_policy.tls_only' <state_bucket_name>
terraform import 'aws_dynamodb_table.lock' <lock_table_name>
```

Si se borra el bucket entero, los estados de los ambientes se pierden con él: por eso el bucket está versionado y la política del módulo `storage` no permite `force_destroy` fuera de `dev`.

## Estado actual

El bootstrap se aplicó el 18 de noviembre de 2026 en la cuenta del proyecto (us-east-1). Verificado en la consola y con
la CLI: bucket `circleguard-tfstate-<id de cuenta>` con control de versiones habilitado y cifrado SSE-S3; tabla
`circleguard-tfstate-lock` con llave `LockID`, modo bajo demanda y protección contra eliminación activa. Los objetos
`dev/`, `stage/` y `prod/terraform.tfstate` contienen el estado de los ambientes. Jenkins recibe la configuración del
backend como credencial `tf-backend-<env>` (archivo `backend.hcl`), nunca desde el repositorio.

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
# y enseguida migra el estado del bootstrap al bucket (ver "Quién custodia el estado del bootstrap")
```

Luego, en cada ambiente, `terraform init -backend-config=backend.hcl` con esos valores y la `key` del ambiente (ver el README de `environments/`).

## Pruebas

```bash
terraform init -backend=false
terraform validate
terraform test   # usa un provider simulado: no crea nada en AWS
```

`tests/bootstrap.tftest.hcl` comprueba la llave `LockID`, el modo on-demand, la protección contra borrado y que `backend_config` apunte a la tabla y active el cifrado.
