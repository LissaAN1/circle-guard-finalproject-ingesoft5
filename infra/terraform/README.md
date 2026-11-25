# Infraestructura como código (Parte 2)

Módulos Terraform reutilizables (TEC-09) y los ambientes dev, stage y prod de
CircleGuard que los consumen, con el estado en un backend remoto (HU-10).

```text
infra/terraform/
  bootstrap/        bucket S3 y tabla DynamoDB del estado remoto            (aplicado)
  environments/     dev, stage y prod que arman los siete módulos           (aplicados)
  modules/
    network/        VPC, subredes públicas, rutas y security group          (TEC-09)
    compute/        nodos del clúster k3s sobre EC2                         (TEC-09)
    registry/       repositorios de imágenes ECR                            (TEC-09)
    storage/        bucket S3 privado para artefactos y reportes            (TEC-09)
    observability/  logs CloudWatch y alarmas de CPU por SNS                (TEC-09)
    cicd_link/      VPC peering, rutas y reglas hacia Jenkins y Nexus       (HU-13)
    finops/         presupuesto por ambiente y escala a cero de los nodos   (HU-25, bonificación)
```

## Estado (cierre de la Parte 2, 22 de noviembre de 2026)

Los cinco módulos de TEC-09 se entregaron primero con pruebas de proveedores simulados. Después se agregaron
`cicd_link` (conectividad privada con la plataforma CI/CD, HU-13) y `finops` (HU-25), y los tres ambientes **se
aplicaron en AWS** (us-east-1): 6 nodos K3s, 3 VPC con peering activo hacia la VPC de Jenkins y Nexus
(`172.31.0.0/16`), estado remoto en S3 con bloqueo en DynamoDB. `terraform plan -detailed-exitcode` devolvió `0` en dev,
stage y prod. Inventario y verificaciones: [`docs/operaciones/hu-10-inventario-aws.md`](../../docs/operaciones/hu-10-inventario-aws.md).

Jenkins ejecuta `plan` y `apply` por ambiente con `ci/scripts/terraform-run.sh` y la imagen fijada
`hashicorp/terraform:1.14.0`; `apply` solo acepta el plan generado en la etapa anterior y, en prod, después de la
aprobación manual. El procedimiento de operación está en
[`docs/operaciones/manual-operaciones-parte-2.md`](../../docs/operaciones/manual-operaciones-parte-2.md).

Diagramas de la arquitectura, los módulos, el estado remoto y las redes:
[`infra/docs/terraform-architecture.md`](../docs/terraform-architecture.md).

## Reglas

- Ninguna credencial, llave ni estado en el repositorio (`.gitignore` lo impide).
- Cada módulo documenta sus variables y salidas en su propio `README.md`.
- Antes de cada commit: `terraform fmt -recursive` y `terraform validate`.
- Trivy IaC (`--severity CRITICAL --exit-code 1`) bloquea el pipeline. La única excepción vigente es `AWS-0104` sobre la
  salida general del security group del clúster, documentada en el propio recurso y en
  [`hu-20-seguridad-plataforma.md`](../../docs/operaciones/hu-20-seguridad-plataforma.md); no elimina el riesgo.