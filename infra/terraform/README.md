# Infraestructura como código (Parte 2)

Módulos Terraform reutilizables para los ambientes dev, stage y prod de
CircleGuard (TEC-09). Los ambientes que los consumen y el backend remoto del
estado se agregan en HU-10.

```text
infra/terraform/
  modules/
    network/        VPC, subredes públicas, rutas y security group   (listo)
    compute/        nodos del clúster                                (pendiente)
    registry/       repositorios de imágenes                         (pendiente)
    storage/        almacenamiento                                   (pendiente)
    observability/  logs y métricas                                  (pendiente)
```

## Reglas

- Ninguna credencial, llave ni estado en el repositorio (`.gitignore` lo impide).
- Cada módulo documenta sus variables y salidas en su propio `README.md`.
- Antes de cada commit: `terraform fmt -recursive` y `terraform validate`.
