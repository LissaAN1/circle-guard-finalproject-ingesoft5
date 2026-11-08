# HU-09 — Respuesta ante fallos del pipeline

## Criterios de aceptación

| # | Criterio | Implementación |
|---|----------|----------------|
| 1 | Cuando falla una etapa, llega una notificación con el enlace al build | `cgNotify` publicada en el commit status de GitHub y, opcionalmente, en un webhook HTTP |
| 2 | Un job parametrizado redespliega una versión anterior en el ambiente elegido | Job `circleguard-rollback` con parámetros `ENVIRONMENT`, `APP_VERSION`, `TARGET_HOST` |
| 3 | El rollback queda evidenciado | El job imprime versión anterior → nueva; `docker compose ps` al final; registro en logs de Jenkins |

---

## 1. Notificación de fallos

### Dónde se activa

`ci/shared-library/vars/cgNotify.groovy` es invocada desde el bloque `post { always { ... } }` de
`circleguardPipeline.groovy`, **antes** de `cleanWs()`, cuando
`currentBuild.currentResult` es `FAILURE` o `UNSTABLE`.

### Canal 1 — GitHub commit status

Publica el estado `failure` / `error` sobre el SHA del commit que disparó el
build. El badge del PR refleja el resultado inmediatamente.

**Requisito:** credencial `github-token` (tipo *Secret text*) en Jenkins con
scopes `repo:status` y `public_repo`.

### Canal 2 — Webhook HTTP (opcional)

Si la variable global de Jenkins `NOTIFY_WEBHOOK_URL` está configurada, se
envía un POST con payload `{"text": "Build FAILED: <job> #<n> — <url>"}` compatible con Slack.

**Configurar en bootstrap:**

```bash
NOTIFY_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../... \
  bash infra/bootstrap-ci.sh
```

---

## 2. Job de rollback

### Ubicación

`ci/rollback/Jenkinsfile` — job `circleguard-rollback` creado por Job DSL en
`infra/bootstrap/jenkins/casc.d/10-ci.yaml`.

### Parámetros

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `ENVIRONMENT` | choice | `dev` / `stage` / `prod` |
| `APP_VERSION` | string | Tag de imagen a redesplegar, e.g. `1.0.0-ci.12.ab12cd3` |
| `TARGET_HOST` | string | IP pública del EC2 (opcional si EC2\_\<ENV\>\_HOST está en env global) |

### Pasos internos

1. Valida parámetros y resuelve IP del host.
2. Copia `ci/rollback/rollback-remote.sh` al EC2 vía SCP.
3. Ejecuta el script en el EC2 vía SSH; al terminar lo elimina.
4. En caso de fallo llama a `cgNotify('FAILURE')`.

### Script remoto

`ci/rollback/rollback-remote.sh` corre **en el EC2** y:

1. Valida el nombre del ambiente y el formato del tag.
2. Lee `/opt/circleguard/environments/.env` (escrito por `deploy-env.sh`).
3. Reemplaza `APP_VERSION` en ese archivo.
4. Ejecuta `docker compose pull` + `docker compose up -d --no-build`.
5. Muestra `docker compose ps` como evidencia del rollback.

---

## 3. Configuración inicial

### 3.1 Credencial SSH para rollback

```bash
# Codificar la clave PEM en base64 (una sola línea, sin saltos)
EC2_SSH_KEY_B64=$(base64 -w0 < ~/.ssh/circleguard-ec2.pem)

EC2_DEV_HOST=<ip-dev>      \
EC2_STAGE_HOST=<ip-stage>  \
EC2_PROD_HOST=<ip-prod>    \
EC2_SSH_KEY_B64="$EC2_SSH_KEY_B64" \
  bash infra/bootstrap-ci.sh
```

El script almacena la clave en `/opt/circleguard/jenkins/ec2-key.pem` (modo
600) y la registra como credencial `ec2-ssh-key` en JCasC.

### 3.2 Variables globales resultantes en Jenkins

| Variable | Descripción |
|----------|-------------|
| `NOTIFY_WEBHOOK_URL` | URL del webhook (vacía deshabilita el canal) |
| `EC2_DEV_HOST` | IP del ambiente dev |
| `EC2_STAGE_HOST` | IP del ambiente stage |
| `EC2_PROD_HOST` | IP del ambiente prod |

---

## 4. Procedimiento de rollback (paso a paso)

1. Identificar la versión estable anterior en el registro de Nexus o en los
   builds anteriores del job `circleguard`.
2. Ir a **Jenkins → circleguard-rollback → Build with Parameters**.
3. Seleccionar `ENVIRONMENT`, ingresar `APP_VERSION` y, si es necesario,
   `TARGET_HOST`.
4. Lanzar el build y verificar el log: debe aparecer la línea
   `Rollback <env> -> <version> complete.`
5. Confirmar estado de los contenedores en la salida de `docker compose ps`.
6. Registrar el incidente y el rollback en Jira (TEC-06).

---

## 5. Evidencia esperada en el log de Jenkins

```
Rolling back dev: 1.0.0-ci.15.abc1234 -> 1.0.0-ci.12.def5678
Pulling 1.0.0-ci.12.def5678 from registry...
Restarting services...
NAME                     IMAGE                                   STATUS
circleguard-dev-api-1    172.31.5.84:8082/cg-api:1.0.0-ci.12.def5678   Up 2 seconds
...
Rollback dev -> 1.0.0-ci.12.def5678 complete. Run verify-env.sh to confirm health.
```
