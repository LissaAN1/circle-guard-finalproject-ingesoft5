# HU-04 - Pipeline de integración continua

Pipeline multibranch en Jenkins que valida cada push y cada pull request.
Se apoya en la plataforma de la HU-01 (Jenkins, SonarQube y Nexus en EC2, TEC-04) y no la reemplaza.

## Qué se entrega

| Pieza | Ubicación |
|---|---|
| `Jenkinsfile` (solo carga la librería) | `Jenkinsfile` |
| Shared Library (etapas) | `ci/shared-library/vars/*.groovy` |
| Reglas de qué se construye | `ci/scripts/changed-units.sh`, `ci/units.conf` |
| Empaquetado y publicación de imágenes | `ci/scripts/package-image.sh`, `ci/scripts/publish-image.sh` |
| Agente de build, plugins, job multibranch, librería | `infra/bootstrap/jenkins/` (`Dockerfile`, `compose.yaml`, `agent/`, `casc.d/10-ci.yaml`) |
| Despliegue idempotente en la EC2 de Jenkins | `infra/bootstrap-ci.sh` + `infra/bootstrap/jenkins/ci-remote.sh` |
| Pruebas offline | `ci/tests/` |

## Criterios de aceptación

| Criterio | Cómo se cumple |
|---|---|
| Un webhook de GitHub dispara el pipeline en cada push | El job multibranch escucha `/github-webhook/`. El webhook llega por el relay `smee.io` (sin abrir el puerto 8080) o directo. Además hay un escaneo periódico cada 10 min como respaldo. |
| Etapas en una Shared Library | `circleguardPipeline` orquesta: checkout, detección de cambios, build, test, análisis (opcional), empaquetado y publicación. |
| Solo corren los servicios modificados; si cambia la raíz, todos | `changed-units.sh`. Cambios en `build.gradle.kts`, `settings.gradle.kts`, `gradle/**`, `Jenkinsfile` o `ci/**` ejecutan todas las unidades. Cambios solo en docs, infra o `.github` no construyen nada. |
| El resultado es un check obligatorio en `dev` y `main` | El plugin GitHub Branch Source publica el estado. Hay que marcarlo como obligatorio en la protección de ramas (ver más abajo). |

## Flujo del pipeline

1. **Checkout:** clona el commit y descarga la rama base para comparar.
2. **Detect changes:** calcula las unidades afectadas (`env.CG_UNITS`). Sin cambios construibles, el build termina en verde sin trabajo.
3. **Build:** `./gradlew assemble` de los servicios afectados.
4. **Test:** `./gradlew test`. Las unidades con `tests=enforce` rompen el build si fallan. Las de `tests=report` solo lo marcan `UNSTABLE` (hoy ninguna: `dashboard` pasó a `enforce` en la HU-05). El informe JUnit queda publicado en Jenkins.
5. **Analysis:** opcional, apagada por defecto (`ENABLE_SONAR=true`). El quality gate es la HU-05.
6. **Package:** imagen Docker por unidad con tag inmutable `<semver>-ci.<build>.<sha7>`, nunca `latest`.
7. **Publish:** solo desde `dev` y `main`, y solo si Jenkins tiene `NEXUS_REGISTRY` configurado. Usa la credencial `nexus-publisher`.

Los builds corren únicamente en el contenedor `build-agent` (el controlador mantiene `numExecutors: 0`).

## Despliegue

Requisitos: los 3 servidores de CI/CD encendidos (`infra/power.sh start jenkins sonarqube nexus`), HU-01 aplicada y tu IP permitida en el SG `cicd`.

```bash
# Mínimo: agente + job multibranch + librería
bash infra/bootstrap-ci.sh

# Completo (los secretos viajan por stdin y quedan solo en la EC2, modo 0600)
export GITHUB_TOKEN=...                       # escaneo de ramas y estados de commit
export NEXUS_REGISTRY=<ip-privada-nexus>:8082
export NEXUS_PUBLISHER_PASSWORD=...           # usuario cg-publisher, se lee en la EC2 de Nexus
export SMEE_URL=https://smee.io/<canal>       # relay de webhooks
bash infra/bootstrap-ci.sh
```

Antes de tocar Jenkins, el script valida la configuración nueva en un contenedor desechable. Si JCasC la rechaza, aborta y el Jenkins de la HU-01 queda intacto.
Es idempotente: repetir el comando conserva volúmenes, credenciales y el secreto del agente.

## Webhook y check obligatorio (pasos manuales en GitHub)

1. **Webhook:** crear un canal en <https://smee.io/new>, pasarlo en `SMEE_URL` y registrar la misma URL en *Settings > Webhooks* del repo (content type `application/json`, eventos `push` y `pull_request`).
2. **Check obligatorio:** en *Settings > Branches*, en las reglas de `dev` y `main`, exigir los checks `continuous-integration/jenkins/pr-merge` (y `continuous-integration/jenkins/branch` si se usa).

## Validación

```bash
python ci/tests/test_changed_units.py   # detección de cambios
python ci/tests/test_ci_config.py       # configuración de Jenkins y librería
```

En Jenkins: el nodo `build-agent` debe aparecer en línea, el job `circleguard` debe escanear las ramas y una rama con cambios en un solo servicio debe mostrar en el log solo esa unidad.

## Límites conocidos

- La configuración de JCasC y la librería se validan al desplegar (pre-flight en la EC2), no en las pruebas offline.
- La etapa `Analysis` (SonarQube) está escrita pero apagada; se activa y se prueba en la HU-05.
- El agente usa el socket de Docker del host: quien controle un build controla el Docker de esa EC2. Es un servidor dedicado a CI y solo construye código del repositorio, pero no debe ejecutar PRs de forks.
- El cliente web (`mobile/`) solo se empaqueta; sus pruebas no corren por el hallazgo de Babel documentado.
- La rama de la librería por defecto es `dev`. Mientras el PR de HU-04 no esté fusionado en `dev`, un build de otra rama no encuentra la librería.
