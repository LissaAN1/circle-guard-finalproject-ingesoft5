# Módulo `registry`

Crea un repositorio de imágenes **Amazon ECR** por cada servicio de CircleGuard
en un ambiente. Los repositorios se nombran `<name>/<servicio>`.

- Etiquetas inmutables por defecto: una versión publicada no se puede sobrescribir.
- Escaneo de vulnerabilidades al publicar cada imagen.
- Cifrado en reposo (AES256).
- Política de ciclo de vida: se conservan solo las últimas `max_image_count` imágenes.

## Variables

| Nombre | Tipo | Por defecto | Descripción |
|:---|:---|:---|:---|
| `name` | string | requerida | Prefijo de los repositorios, por ejemplo `circleguard-dev`. |
| `environment` | string | requerida | `dev`, `stage` o `prod`. |
| `services` | list(string) | requerida | Servicios que tendrán repositorio. Sin duplicados, en minúsculas. |
| `image_tag_mutability` | string | `IMMUTABLE` | `MUTABLE` o `IMMUTABLE`. |
| `scan_on_push` | bool | `true` | Escanear cada imagen al publicarla. |
| `max_image_count` | number | `20` | Imágenes recientes que se conservan por repositorio (mínimo 1). |
| `force_delete` | bool | `false` | Permite destruir repositorios con imágenes (solo para dev). |
| `tags` | map(string) | `{}` | Etiquetas adicionales. |

## Requisitos

Terraform `>= 1.9.0` y provider `hashicorp/aws ~> 5.0`.

## Salidas

| Nombre | Descripción |
|:---|:---|
| `repository_urls` | Mapa servicio → URL del repositorio ECR. |
| `repository_arns` | Mapa servicio → ARN del repositorio ECR. |

## Ejemplo

```hcl
module "registry" {
  source      = "../../modules/registry"
  name        = "circleguard-dev"
  environment = "dev"
  services = [
    "auth-service", "dashboard-service", "file-service", "form-service",
    "gateway-service", "identity-service", "notification-service", "promotion-service",
  ]
}
```

## Pruebas

```bash
terraform init -backend=false
terraform validate
terraform test   # usa un provider simulado: no crea nada en AWS
```

`tests/registry.tftest.hcl` comprueba los valores seguros por defecto (etiquetas inmutables, escaneo al publicar, nombres con prefijo, política de ciclo de vida) y que se rechacen listas de servicios vacías, duplicadas o con nombres inválidos, una mutabilidad desconocida, una retención de 0 imágenes y un ambiente desconocido.
