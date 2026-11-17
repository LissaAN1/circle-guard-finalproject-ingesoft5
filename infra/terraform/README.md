# Infraestructura como código (Parte 2)

Módulos Terraform reutilizables (TEC-09) y los ambientes dev, stage y prod de
CircleGuard que los consumen, con el estado en un backend remoto (HU-10).

```text
infra/terraform/
  bootstrap/        bucket S3 y tabla DynamoDB del estado remoto     (listo)
  environments/     dev, stage y prod que arman los cinco módulos    (listo)
  modules/
    network/        VPC, subredes públicas, rutas y security group   (listo)
    compute/        nodos del clúster k3s sobre EC2                  (listo)
    registry/       repositorios de imágenes ECR                     (listo)
    storage/        bucket S3 privado para artefactos y reportes     (listo)
    observability/  logs CloudWatch y alarmas de CPU por SNS         (listo)
```

Diagramas de la arquitectura, los módulos, el estado remoto y las redes:
[`infra/docs/terraform-architecture.md`](../docs/terraform-architecture.md).

## Reglas

- Ninguna credencial, llave ni estado en el repositorio (`.gitignore` lo impide).
- Cada módulo documenta sus variables y salidas en su propio `README.md`.
- Antes de cada commit: `terraform fmt -recursive` y `terraform validate`.
