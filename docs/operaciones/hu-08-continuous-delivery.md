# HU-08 — Entrega continua por ambientes

## Flujo de despliegue

```
dev branch  →  build/test/package/publish  →  Deploy Dev   (automático)
main branch →  build/test/package/publish  →  Deploy Stage (automático)
                                            →  E2E Tests    (HU-07 stub por ahora)
                                            →  Approve Prod (input manual, 30 min timeout)
                                            →  Deploy Prod  (automático tras aprobación)
```

Los stages de despliegue se saltan automáticamente si:
- `NEXUS_REGISTRY` no está configurado (no hay imágenes publicadas)
- No se detectaron unidades cambiadas (`CG_IMAGE_TAG` no existe)
- El build es un PR (`CHANGE_ID` está definido)

## Requisitos antes del primer despliegue

1. `deploy-env.sh` de HU-02 ya ejecutado en cada EC2 (`/opt/circleguard/environments/.env` existe)
2. `bootstrap-ci.sh` ejecutado con las variables opcionales:
   ```bash
   EC2_DEV_HOST=<ip-dev> \
   EC2_STAGE_HOST=<ip-stage> \
   EC2_PROD_HOST=<ip-prod> \
   EC2_SSH_KEY_B64=$(base64 -w0 < ~/.ssh/circleguard-key.pem) \
     bash infra/bootstrap-ci.sh
   ```
3. Credential `ec2-ssh-key` visible en **Manage Jenkins → Credentials**

## Qué hace deploy-remote.sh en el EC2

1. Valida el nombre del ambiente y el formato de la versión
2. Lee `APP_VERSION` actual de `/opt/circleguard/environments/.env`
3. Reemplaza `APP_VERSION=<nueva>`
4. Ejecuta `docker compose pull` para bajar las nuevas imágenes desde Nexus
5. Ejecuta `docker compose up -d --no-build` para reiniciar con la nueva versión
6. Imprime `docker compose ps` como evidencia

## Aprobación de prod

El stage **Approve Prod** lanza un `input` en Jenkins. El responsable de release entra al build
en `http://<jenkins>:8080/job/circleguard/job/main/<N>/` y hace clic en **Approve**.
Si nadie aprueba en 30 minutos, el build se marca `ABORTED`.

## Pendiente: E2E (HU-07)

El stage `E2E Tests` llama a `cgE2E()` que actualmente es un stub. Cuando HU-07 esté lista,
`ci/shared-library/vars/cgE2E.groovy` se reemplaza con la implementación de Playwright.
Hasta entonces la promoción a stage no está bloqueada por los tests.
