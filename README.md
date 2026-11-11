# CircleGuard Monorepo

**Absolute Privacy. High-Speed Containment. Secure Campus.**

CircleGuard is a state-of-the-art university contact tracing and fencing system designed to identify interconnected contact groups ("Circles") and apply rapid health fences while preserving individual anonymity.

> **Sobre este repositorio.** CircleGuard es un producto preexistente: sus microservicios, su cliente Expo y su visión funcional pertenecen al proyecto original. Este monorepo se usa como base del **Proyecto Final de Ingeniería de Software V (Universidad Icesi, 2026-2)**. El equipo del curso **no es autor de los microservicios originales**. Su aporte es dotar al producto de infraestructura reproducible en AWS, empaquetamiento Docker, un pipeline CI/CD en Jenkins, análisis de calidad con SonarQube, pruebas automatizadas y despliegue entre ambientes.

---

## Tabla de contenido

1. [Presentación y propósito](#1-presentación-y-propósito)
2. [Arquitectura y tecnologías](#2-arquitectura-y-tecnologías)
3. [Estructura del repositorio](#3-estructura-del-repositorio)
4. [Requisitos previos](#4-requisitos-previos)
5. [Desarrollo local](#5-desarrollo-local)
6. [Infraestructura AWS: encendido, apagado y verificación](#6-infraestructura-aws-encendido-apagado-y-verificación)
7. [Acceso a Jenkins](#7-acceso-a-jenkins)
8. [Reproducción y configuración de Jenkins](#8-reproducción-y-configuración-de-jenkins)
9. [Funcionamiento del pipeline CI/CD](#9-funcionamiento-del-pipeline-cicd)
10. [Despliegues, validación y rollback](#10-despliegues-validación-y-rollback)
11. [Solución de problemas y limitaciones](#11-solución-de-problemas-y-limitaciones)
12. [Referencias](#12-referencias)

---

## 1. Presentación y propósito

### 1.1 Producto original

#### Vision & Mission

Our vision is a university campus where health containment speed outpaces lab confirmation timelines without compromising student privacy. CircleGuard leverages campus-native intelligence—class schedules and WiFi infrastructure—to deliver a human-validated, graph-based protection ecosystem.

#### Key Differentiators
- **Privacy-as-Code**: Zero real-name exposure outside a secure Health Center vault.
- **Recursive Containment**: Status promotion cascades (Suspect → Probable → Confirmed) that trigger in milliseconds.
- **Campus Integration**: Smart check-ins using existing WiFi AP triangulation and Bluetooth Low Energy (BLE).

#### Success Metrics (product targets)

> Objetivos definidos por el producto original:

| Metric | Target | Measurement |
|:---|:---|:---|
| **Containment Speed** | < 60 Seconds | Automated test of promotion engine cascade |
| **Privacy Compliance** | 100% Anonymity | Penetration test on graph database (Zero real names) |
| **Check-in Adoption** | > 70% | Analytics on scheduled class contact validation |
| **False Positive Rate** | < 15% | Post-fence surveys of actual vs. suspected contact |
| **System Uptime** | 99.5% | 7:00 AM – 10:00 PM (Academic Peak Hours) |

#### Product Roadmap (original)

> Hoja de ruta funcional del producto original, que se conserva como referencia. No forma parte del alcance DevOps del curso.

**Phase 1: MVP — The Intelligence Core**
- [x] Status Promotion Machine (Suspect → Probable → Confirmed).
- [x] Temporal graph with 14-day TTL edges.
- [x] Multi-channel fence notifications (Push/Email/SMS).
- [ ] Health Center de-identification console.

**Phase 2: Growth — Spatial Intelligence**
- [ ] WiFi AP triangulation integration.
- [ ] Campus entry validation (Gatekeeper) QR integration.
- [ ] LMS integration for "Remote Attendance" status automation.

**Phase 3: Vision — Full Ecosystem**
- [ ] Off-campus circle detection via P2P Bluetooth.
- [ ] Global Health Dashboard with hotspot visualization.
- [ ] Lab API bridge for automated test result ingestion.

### 1.2 Intervención DevOps — Parte 1 (Sprints 0 y 1)

El equipo de Ingeniería de Software V añadió al producto base lo siguiente:

| Entregable | Qué se agregó |
|:---|:---|
| E1.1 Gestión ágil | Scrum en Jira, Product Backlog, GitFlow simplificado (`feature/*` → `dev` → `main`), rulesets en GitHub, plantilla de PR y validación de Conventional Commits. |
| E1.2 Infraestructura | Seis instancias EC2 (Jenkins, SonarQube, Nexus, `dev`, `stage` y `prod`), aprovisionadas y configuradas con scripts Bash idempotentes en `infra/`. |
| E1.3 Empaquetamiento | Dockerfiles multi-stage sin root para los 8 servicios y el cliente web, imágenes versionadas y publicadas en Nexus, y Docker Compose por ambiente con healthchecks. |
| E1.4 Pipeline CI | Job multibranch en Jenkins con Shared Library, ejecución selectiva por unidad, pruebas, quality gate de SonarQube, empaquetado y publicación. |
| E1.5 Entrega continua | Despliegue automático a `dev` y `stage`, aprobación manual para `prod` y rollback automático cuando el despliegue falla. |
| E1.6 Pruebas | Cobertura JaCoCo con quality gate de líneas ≥ 60 %, pruebas de integración con Testcontainers y tres flujos E2E con Playwright. |
| E1.7 Cambios y release | Proceso de gestión de cambios, versionado SemVer y generación de release notes con `infra/release/`. |
| E1.8 Documentación | Este README, las guías de `infra/` y `docs/`, el informe de la Parte 1 e `IAG_REGISTRO.md`. |

### 1.3 Previsto para la Parte 2

- Despliegue de `notification`, `file` y `dashboard`. En la Parte 1 estos servicios se compilan, se prueban y se empaquetan, pero no se despliegan.
- Orquestación con **Kubernetes** e infraestructura como código con **Terraform**.
- Observabilidad: métricas, logs y trazas.

---

## 2. Arquitectura y tecnologías

### 2.1 Architecture Overview (original)

CircleGuard follows a **Microservice Architecture** built on a **Hybrid Data Model**.

1. **Status Promotion Machine**: Uses **Neo4j** for recursive graph traversals to identify contacts within a 14-day temporal window.
2. **Anonymization Vault**: A segregated **PostgreSQL** vault handles salted-hash identity mapping, designed with **FERPA** requirements in mind.
3. **Event-Driven Core**: **Apache Kafka** manages asynchronous status changes, audit logs, and notification dispatches.

### 2.2 Services Directory

| Servicio | Módulo Gradle | Puerto | Responsabilidad (original) | Parte 1 |
|:---|:---|:---:|:---|:---|
| Auth | `services:circleguard-auth-service` | 8180 | Dual-chain LDAP (University) / Local (Guest) auth with Dynamic RBAC. | Desplegado |
| Identity | `services:circleguard-identity-service` | 8083 | Cryptographic vault for anonymizing real identities. | Desplegado |
| Promotion | `services:circleguard-promotion-service` | 8088 | The status engine (Recursive Graph Processing). | Desplegado |
| Form | `services:circleguard-form-service` | 8086 | Dynamic health questionnaire engine. | Desplegado |
| Gateway | `services:circleguard-gateway-service` | 8087 | Campus entry validation via signed, time-limited QR tokens. | Desplegado |
| Notification | `services:circleguard-notification-service` | 8082 | Multi-channel dispatcher (Push/Email/SMS). | CI y empaquetado |
| Dashboard | `services:circleguard-dashboard-service` | 8084 | Geospatial hotspot analytics (Privacy-preserving). | CI y empaquetado |
| File | `services:circleguard-file-service` | 8085 | Secure certificate and document storage (S3-compatible). | CI y empaquetado |
| Web client | `mobile/` (Expo) | 80 → 8080 | Interfaz web servida por Nginx (proxy inverso hacia los servicios). | Desplegado |

### 2.3 Technical Stack

| Layer | Technology | Notas |
|:---|:---|:---|
| **Backend** | Spring Boot 3.2.4 / Java 21 / Kotlin 1.9.24 | El README original indicaba Spring Boot 4; la versión real está en `build.gradle.kts`. |
| **Build** | Gradle 8.14 (Wrapper) / JaCoCo 0.8.12 | Toolchain Java 21. |
| **Graph DB** | Neo4j 5.26 | |
| **Relational DB** | PostgreSQL 16 | |
| **Message Bus** | Apache Kafka (Confluent 7.6.0) + Zookeeper | |
| **Caching** | Redis 7.2 | |
| **Directory** | OpenLDAP (osixia 1.5.0) | |
| **Mobile/Web** | Expo (React Native) | La imagen web se construye con Node 20 y se sirve con `nginx-unprivileged`. |
| **Infra (Parte 1)** | AWS EC2 + Docker Compose | Kubernetes corresponde a la Parte 2. |

### 2.4 Plataforma DevOps (Parte 1)

| Componente | Ubicación | Responsabilidad |
|:---|:---|:---|
| Jenkins | EC2 `circleguard-jenkins` (`c7i-flex.large`), puerto 8080 | Controlador sin ejecutores (`numExecutors: 0`), configurado con Jenkins Configuration as Code (JCasC). |
| Agente `build-agent` | Contenedor en la EC2 de Jenkins | Ejecuta todos los builds (etiquetas `docker gradle jdk21`) con acceso al socket Docker del host. |
| SonarQube + PostgreSQL | EC2 `circleguard-sonarqube`, puerto 9000 | Análisis estático y quality gate de cobertura de líneas ≥ 60 %. |
| Nexus Repository | EC2 `circleguard-nexus`, 8081 (UI) y 8082 (registro Docker) | Repositorio `circleguard-docker` y cuentas técnicas `cg-publisher` y `cg-reader`. |
| Ambientes | EC2 `circleguard-dev`, `circleguard-stage` y `circleguard-prod` (`m7i-flex.large`) | Por ambiente, 12 contenedores con Docker Compose: 5 servicios núcleo, el cliente web y 6 servicios de middleware. |
| Red | Grupos de seguridad `circleguard-sg-cicd/dev/stage/prod` | Los ambientes no se referencian entre sí, así que el tráfico entre ellos queda denegado. SSH solo con llave. |
| Webhooks | Contenedor `webhook-relay` (smee.io) | Reenvía los eventos de GitHub a Jenkins sin exponer el puerto 8080 a Internet. |

---

## 3. Estructura del repositorio

```text
.
├── services/                    # [Base] 8 microservicios Spring Boot (+ Dockerfile multi-stage por servicio [DevOps])
├── mobile/                      # [Base] Cliente Expo; Dockerfile, nginx.conf y docker-entrypoint.sh [DevOps]
├── docker-compose.dev.yml       # [Base] Middleware para desarrollo local
├── init-db.sql                  # [Base] Inicialización de PostgreSQL local
├── build.gradle.kts             # [Base] Build raíz (+ JaCoCo y tarea integrationTest [DevOps])
├── settings.gradle.kts          # [Base] Módulos Gradle
├── Jenkinsfile                  # [DevOps] Carga la Shared Library y llama a circleguardPipeline()
├── ci/                          # [DevOps] Integración continua
│   ├── shared-library/vars/     #   Etapas del pipeline (cgCheckout, cgTest, cgDeploy, cgE2E, ...)
│   ├── scripts/                 #   changed-units.sh, package-image.sh, publish-image.sh, unit-info.sh
│   ├── deploy/deploy-remote.sh  #   Despliegue con rollback automático en la EC2 destino
│   ├── tests/                   #   Pruebas offline de la configuración CI (Python)
│   └── units.conf               #   Unidades, política de pruebas y quality gate
├── infra/                       # [DevOps] AWS y plataforma CI/CD
│   ├── *.sh                     #   bootstrap-*, status, power, verify, teardown, create-budget
│   ├── bootstrap/               #   Compose y configuración de Jenkins (JCasC), SonarQube y Nexus
│   ├── environments/            #   Compose por ambiente y scripts create/validate/deploy/verify
│   ├── release/                 #   version.sh, changelog.sh, release.sh, build-images.sh
│   ├── docs/costs.md            #   Estimación de costos y apagado
│   └── README.md                #   Manual detallado de infraestructura
├── tests/e2e-playwright/        # [DevOps] Suite E2E (HU-07) y sus runners
├── docs/
│   ├── agil/                    # [DevOps] Documentos ágiles 00–08
│   └── operaciones/             # [DevOps] Runbooks de pipeline, quality gate, entrega continua y hallazgos
├── .github/                     # [DevOps] Plantilla de PR y workflow de validación de commits
├── .githooks/                   # [DevOps] Validación del asunto de los commits
├── CHANGELOG.md                 # [DevOps] Release notes (generadas con infra/release/release.sh)
├── IAG_REGISTRO.md              # [DevOps] Registro de uso de IA generativa
└── README.md
```

---

## 4. Requisitos previos

| Herramienta | Desarrollo local | Administración AWS / CI | Notas |
|:---|:---:|:---:|:---|
| Git | ✔ | ✔ | Acceso al repositorio privado `LissaAN1/circle-guard-finalproject-ingesoft5`. |
| Docker + Docker Compose v2 | ✔ | — | Middleware local y pruebas con Testcontainers. |
| Java 21 | ✔ | — | Se usa el Gradle Wrapper (`./gradlew`); no hace falta instalar Gradle. |
| Node.js 20 + npm | ✔ | — | Cliente Expo (`mobile/`). |
| Bash | ✔ | ✔ | En Windows, Git Bash o WSL. |
| AWS CLI v2 | — | ✔ | Perfil IAM autorizado (EC2 y, para la red, `ec2:AuthorizeSecurityGroupIngress`). |
| Llave SSH | — | ✔ | Llave del proyecto (`~/.ssh/circleguard-key.pem` por defecto, o `CIRCLEGUARD_SSH_KEY`). Nunca en Git. |
| `infra/config.env` | — | ✔ | Parámetros no secretos de infraestructura (región, nombres, tamaños). |
| Privilegios de administrador | — | Solo bootstrap | Reproducir la plataforma exige credenciales AWS y SSH de operador; consultar Jenkins no. |

---

## 5. Desarrollo local

### 5.1 Middleware

```bash
docker compose -f docker-compose.dev.yml up -d
docker compose -f docker-compose.dev.yml ps
```

*Middleware includes: PostgreSQL, Neo4j, Kafka, Zookeeper, Redis, and OpenLDAP.* Las credenciales de `docker-compose.dev.yml` son solo para desarrollo local; los ambientes de AWS usan secretos generados por `infra/environments/create-env.sh`.

### 5.2 Build & Run

```bash
./gradlew assemble                                        # compila todos los servicios
./gradlew :services:circleguard-auth-service:bootRun      # ejecuta un servicio
./gradlew bootRun --parallel                              # ejecuta todos (consume mucha memoria)
```

Cada servicio expone `GET /actuator/health` en su puerto (tabla 2.2). El README original mencionaba Swagger UI, pero el código actual no incluye springdoc/OpenAPI, así que esa interfaz no está disponible.

### 5.3 Pruebas

| Comando | Alcance |
|:---|:---|
| `./gradlew test` | Pruebas unitarias. Excluye la etiqueta `integration` y genera el informe JaCoCo. |
| `./gradlew :services:circleguard-form-service:test` | Pruebas unitarias de un solo servicio. |
| `./gradlew :services:circleguard-form-service:integrationTest :services:circleguard-promotion-service:integrationTest` | Pruebas de integración (`@Tag("integration")`). **Requieren Docker.** |
| `python -m pytest ci/tests/ -q` | Suite completa offline de la configuración CI (`test_changed_units.py`, `test_ci_config.py`, `test_deploy_remote.py`, `test_hu07_pipeline.py`). |

Las pruebas de integración usan **Testcontainers** para levantar instancias efímeras de PostgreSQL, Kafka, Redis y Neo4j. El informe de cobertura queda en `services/<servicio>/build/reports/jacoco/test/html/index.html`.

### 5.4 Frontend (Expo)

```bash
cd mobile
npm install
```

| Platform | Command | Notes |
|:---|:---|:---|
| **Development Menu** | `npm run start` | Opens the Expo Go start-up menu. |
| **Android** | `npm run android` | Requires Android Studio / Emulator or a connected device. |
| **iOS** | `npm run ios` | Requires macOS with Xcode / Simulator installed. |
| **Web Browser** | `npm run web` | Launches the app in your default browser. |
| **Tests** | `npm run test` | Jest unit and component tests. Se ejecutan fuera del pipeline (`web` tiene `tests=skip` en `ci/units.conf`). |

---

## 6. Infraestructura AWS: encendido, apagado y verificación

> Las instancias se detienen fuera de las sesiones de trabajo para controlar costos. **Las IP públicas cambian cada vez que una instancia se detiene y se vuelve a iniciar.**

| Tipo de comando | Comandos |
|:---|:---|
| **Solo consulta** (no cambia nada) | `infra/status.sh`, `infra/verify.sh`, `infra/bootstrap-verify.sh`, `infra/environments/verify-env.sh`, `infra/environments/preflight-ec2.sh` |
| **Cambia el estado o la facturación** | `infra/power.sh start\|stop` |
| **Crea o reconfigura recursos** (solo con autorización) | `bootstrap-keypair.sh`, `bootstrap-network.sh`, `bootstrap-instances.sh`, `bootstrap-cicd.sh`, `bootstrap-ci.sh`, `environments/deploy-env.sh` |
| **Destructivo** (no usar para revisar) | `infra/teardown.sh`, `docker compose down -v`, `docker volume rm` o `docker volume prune` |

### Secuencia operativa

```bash
# 1. Credenciales AWS y llave SSH (valores del operador autorizado)
export AWS_PROFILE=<perfil-autorizado>
export CIRCLEGUARD_SSH_KEY="$HOME/.ssh/circleguard-key.pem"

# 2. Comprobar identidad y acceso
aws sts get-caller-identity

# 3-4. Estado de las instancias e identificación de las detenidas
bash infra/status.sh

# 5. Encender solo lo necesario. Sintaxis: power.sh start|stop [server ...]
#    Servidores: jenkins sonarqube nexus dev stage prod (sin argumentos actúa sobre todos)
bash infra/power.sh start jenkins sonarqube nexus      # plataforma CI/CD
bash infra/power.sh start dev                          # ambientes según la tarea

# 6. Volver a consultar para obtener las IP públicas nuevas
bash infra/status.sh

# 7. Verificar los servicios (encender una EC2 no garantiza que sus servicios estén sanos)
bash infra/bootstrap-verify.sh                         # Jenkins, SonarQube, Nexus (solo lectura)
bash infra/environments/verify-env.sh dev              # ambiente: healthchecks y digests (solo lectura)

# 8. Apagar al terminar, si ningún integrante está usando las instancias
bash infra/power.sh stop dev stage prod
bash infra/power.sh stop jenkins sonarqube nexus
bash infra/status.sh
```

Detener una instancia suspende la facturación de cómputo, pero los volúmenes EBS siguen generando costo; los detalles están en `infra/docs/costs.md`. **No ejecute** `bootstrap-instances.sh` sobre una cuenta que ya tiene la infraestructura: está pensado para el aprovisionamiento inicial (TEC-04). Los pasos completos de aprovisionamiento están en [`infra/README.md`](infra/README.md).

---

## 7. Acceso a Jenkins

| Recurso | Valor |
|:---|:---|
| URL actual | **http://34.239.94.4:8080/** |
| Job multibranch | `http://34.239.94.4:8080/job/circleguard/` |
| Usuario del docente | `JENKINS_TEACHER_USER=teacher` |
| Contraseña | `JENKINS_TEACHER_PASSWORD=<contraseña proporcionada por el equipo>` |

> La plataforma Jenkins se aloja en una instancia AWS EC2 que puede permanecer apagada para controlar costos. Si la URL no responde, consulte el estado de la instancia y su dirección pública actual. En caso de no disponer de acceso administrativo, comuníquese con el equipo responsable mediante Microsoft Teams para coordinar el encendido o solicitar la URL vigente.

La cuenta del docente tiene solo los permisos `Overall/Read`, `Job/Read` y `View/Read`, definidos en `infra/bootstrap/jenkins/casc.yaml`. Con ellos puede consultar los builds, los logs, los resultados de pruebas, la cobertura y el informe de Playwright. No puede lanzar builds, aprobar el paso a producción ni administrar Jenkins. La contraseña la genera el bootstrap y solo existe en `/opt/circleguard/jenkins/jenkins.secrets.env`, dentro de la EC2 de Jenkins.

---

## 8. Reproducción y configuración de Jenkins

### 8.1 Tres escenarios distintos

| Escenario | Quién | Comando | Efecto |
|:---|:---|:---|:---|
| **Consultar una instancia ya configurada** | Docente o integrante | Navegador (sección 7) y, si tiene AWS, `bash infra/status.sh` | Ninguno. |
| **Bootstrap inicial de la plataforma (HU-01)** | Administrador | `JENKINS_TEACHER_USER=teacher bash infra/bootstrap-cicd.sh` y luego `bash infra/bootstrap-verify.sh` | Instala Jenkins, SonarQube y Nexus con Docker Compose sobre las EC2 existentes. Es idempotente y conserva credenciales y volúmenes. |
| **Configurar o actualizar el pipeline (HU-04/05/08)** | Administrador | `bash infra/bootstrap-ci.sh` con las variables de 8.2 | Instala el agente, la Shared Library y el job multibranch, y opcionalmente el relay de webhooks, el análisis de SonarQube y la publicación en Nexus. Antes de tocar el Jenkins activo valida la configuración JCasC en un contenedor desechable. |

### 8.2 Variables de entorno

| Variable | Propósito | Oblig. | Dónde se configura | Sensible | Cómo se obtiene |
|:---|:---|:---:|:---|:---:|:---|
| `JENKINS_TEACHER_USER` | Login de la cuenta de solo lectura | Sí (1.ª vez) | Entorno de `bootstrap-cicd.sh` | No | Lo define el equipo (`teacher`). |
| `GITHUB_TOKEN` | Escaneo multibranch y estados de commit | Opcional* | Entorno de `bootstrap-ci.sh` → `ci.secrets.env` (EC2) | **Sí** | Token de GitHub de un integrante (scopes `repo:status`, `public_repo`). |
| `NEXUS_REGISTRY` | Registro Docker (`<ip-privada-nexus>:8082`); habilita Publish y los despliegues | Opcional* | Entorno de `bootstrap-ci.sh` → JCasC (global) | No | IP privada de Nexus en `infra/status.sh`. |
| `NEXUS_PUBLISHER_PASSWORD` | Contraseña de `cg-publisher` | Con Publish | Entorno de `bootstrap-ci.sh` | **Sí** | Se lee en la EC2 de Nexus (`/opt/circleguard/nexus/nexus.secrets.env`). |
| `SONAR_HOST_URL` | `http://<ip-privada-sonarqube>:9000`; habilita Analysis | Opcional* | Entorno de `bootstrap-ci.sh` → JCasC (global) | No | IP privada de SonarQube en `infra/status.sh`. |
| `SONAR_TOKEN` | Token de análisis | No | Entorno de `bootstrap-ci.sh` | **Sí** | Si se omite, el script lo obtiene automáticamente de la EC2 de SonarQube. |
| `SMEE_URL` | Canal `https://smee.io/<canal>` para webhooks | Opcional | Entorno de `bootstrap-ci.sh` | Semi | Se crea en smee.io y se registra en *Settings › Webhooks* de GitHub. |
| `NOTIFY_WEBHOOK_URL` | Webhook compatible con Slack para fallos | Opcional | Lo acepta `ci-remote.sh` (ver 8.4) → JCasC (global) | **Sí** | Webhook del canal del equipo. |
| `EC2_DEV_HOST`, `EC2_STAGE_HOST`, `EC2_PROD_HOST` | IP pública de cada ambiente para `cgDeploy` | Con CD | Lo acepta `ci-remote.sh` (ver 8.4) → JCasC (global) | No | `infra/status.sh`. **Cambian al reiniciar las EC2.** |
| `EC2_SSH_KEY_B64` | Llave SSH en base64 que crea la credencial `ec2-ssh-key` | Con CD | Lo acepta `ci-remote.sh` (ver 8.4) | **Sí** | `base64 -w0 < ~/.ssh/circleguard-key.pem`, por stdin. Nunca como argumento. |
| `CG_PROD_APPROVERS` | Usuarios autorizados a aprobar `prod` | Con prod | **Manual:** *Manage Jenkins › System › Global properties* | No | Lo decide el equipo (Product Owner). |
| `CG_ENABLE_PROD_RELEASE` | Habilita Approve Prod y Deploy Prod (`true`) | Con prod | **Manual:** *Global properties* | No | Activar solo para un release autorizado, con stage validado. **No dejarlo activo por defecto.** |
| `CG_INTEGRATION_ENABLED` | `false` omite Integration Test | No | Global properties | No | Solo para diagnóstico. No usar al generar evidencia. |
| `TC_HOST_OVERRIDE` | Host que usa Testcontainers si no alcanza los contenedores | No | Global properties | No | Gateway del host Docker, según el diagnóstico. |

\* Sin esta variable la etapa correspondiente se omite y el pipeline continúa: sin `SONAR_HOST_URL` no hay Analysis, y sin `NEXUS_REGISTRY` no hay Publish ni Deploy.

Los secretos viajan siempre por **stdin a través de SSH**. Quedan solo en la EC2 de Jenkins (`/opt/circleguard/jenkins/ci.secrets.env`, modo 0600) y no se escriben en el repositorio ni en los argumentos de los comandos.

### 8.3 Credenciales de Jenkins (IDs exactos)

| ID | Tipo | Uso | Cómo se provisiona |
|:---|:---|:---|:---|
| `github-token` | Secret text | Estados de commit desde el pipeline | `ci-remote.sh` (JCasC), si existe `GITHUB_TOKEN` |
| `github-scan` | Username/password | Escaneo multibranch y webhooks del job `circleguard` | `ci-remote.sh` (JCasC), si existe `GITHUB_TOKEN` |
| `nexus-publisher` | Username/password (`cg-publisher`) | Etapa Publish | `ci-remote.sh` (JCasC), si existe `NEXUS_PUBLISHER_PASSWORD` |
| `sonar-token` | Secret text | Etapa Analysis | `ci-remote.sh` (JCasC), si existe `SONAR_TOKEN` (obtenido automáticamente) |
| `ec2-ssh-key` | SSH private key (usuario `ubuntu`) | Deploy Dev, Stage y Prod | `ci-remote.sh` (JCasC), si existe `EC2_SSH_KEY_B64` |
| `circleguard-dev-ssh` / `circleguard-stage-ssh` | SSH private key | Túnel E2E hacia dev y stage | **Manual** (*Manage Jenkins › Credentials*) |
| `circleguard-dev-host` / `circleguard-stage-host` | Secret text | IP del ambiente para la suite E2E | **Manual** |
| `circleguard-e2e-survey` / `circleguard-stage-e2e-survey` | Username/password | Cuenta dedicada del flujo de cuestionario | **Manual** |
| `circleguard-e2e-gate` / `circleguard-stage-e2e-gate` | Username/password | Cuenta dedicada del flujo de validación de acceso | **Manual** |

La Shared Library `circleguard-ci` se declara de forma global en JCasC (`infra/bootstrap/jenkins/casc.d/10-ci.yaml`): se carga desde `ci/shared-library/` del mismo repositorio y su definición no usa ninguna credencial propia. El `Jenkinsfile` la carga y llama a `circleguardPipeline()`.

**Dónde vive cada configuración:**

| Ámbito | Contenido |
|:---|:---|
| Global (JCasC) | Nodo `build-agent`, Shared Library y las variables globales `NEXUS_REGISTRY`, `SONAR_HOST_URL`, `NOTIFY_WEBHOOK_URL` y `EC2_*_HOST`. |
| Job (Job DSL en JCasC) | Job multibranch `circleguard`: origen GitHub, `scriptPath('Jenkinsfile')` y escaneo periódico cada 10 minutos. |
| Automático (scripts) | Secretos, credenciales, `DOCKER_GID` y `insecure-registries` en la EC2 de Jenkins. |
| Manual (no reproducible por scripts) | `CG_PROD_APPROVERS`, `CG_ENABLE_PROD_RELEASE` y las credenciales E2E `circleguard-*` (ver sección 11.2). |

### 8.4 Comandos de configuración

Secuencia después del bootstrap de la plataforma (`bootstrap-cicd.sh` y `bootstrap-verify.sh`, sección 6):

1. **CI con `bootstrap-ci.sh`** (agente, Shared Library, job multibranch y credenciales de CI). Los secretos se exportan en la sesión, nunca se escriben en archivos del repo:

```bash
# Mínimo: agente, Shared Library y job multibranch
bash infra/bootstrap-ci.sh

# Completo (CI)
export GITHUB_TOKEN=<valor-a-configurar>
export NEXUS_REGISTRY=<ip-privada-nexus>:8082
export NEXUS_PUBLISHER_PASSWORD=<valor-a-configurar>
export SONAR_HOST_URL=http://<ip-privada-sonarqube>:9000
export SMEE_URL=https://smee.io/<canal>
bash infra/bootstrap-ci.sh
```

   En la versión actual, `bootstrap-ci.sh` solo reenvía `JENKINS_PUBLIC_URL`, `NEXUS_REGISTRY`, `SONAR_HOST_URL`, `SONAR_TOKEN`, `GITHUB_TOKEN`, `NEXUS_PUBLISHER_PASSWORD` y `SMEE_URL`.

2. **Direcciones EC2 y llave de despliegue con `ci-remote.sh`.** El script queda instalado por el paso 1 en `/opt/circleguard/jenkins/ci-remote.sh` (EC2 de Jenkins), se ejecuta como root y lee desde stdin líneas `CLAVE=valor`; las claves que no se envían conservan su valor anterior. Tome las IP públicas de `bash infra/status.sh`:

```bash
JENKINS_IP=<ip-publica-jenkins>
{
  printf 'EC2_DEV_HOST=%s\n'   '<ip-publica-dev>'
  printf 'EC2_STAGE_HOST=%s\n' '<ip-publica-stage>'
  printf 'EC2_PROD_HOST=%s\n'  '<ip-publica-prod>'
  printf 'EC2_SSH_KEY_B64=%s\n' "$(base64 -w0 < "$CIRCLEGUARD_SSH_KEY")"
  # Opcional: printf 'NOTIFY_WEBHOOK_URL=%s\n' '<valor-a-configurar>'
} | ssh -i "$CIRCLEGUARD_SSH_KEY" ubuntu@"$JENKINS_IP" 'sudo bash /opt/circleguard/jenkins/ci-remote.sh'
```

3. **Comprobación en Jenkins:** la credencial `ec2-ssh-key` aparece en *Manage Jenkins › Credentials*, el nodo `build-agent` está en línea y se ejecuta *Scan Repository Now* en el job `circleguard`.
4. **Configuración manual:** `CG_PROD_APPROVERS`, `CG_ENABLE_PROD_RELEASE` y las credenciales E2E `circleguard-*` (tabla de 8.3).
5. **Tras reiniciar las EC2 de ambientes:** repita el paso 2 con las nuevas IP públicas y actualice `circleguard-dev-host` / `circleguard-stage-host`.

El procedimiento detallado está en [`docs/operaciones/hu-04-pipeline-ci.md`](docs/operaciones/hu-04-pipeline-ci.md) y [`docs/operaciones/hu-08-continuous-delivery.md`](docs/operaciones/hu-08-continuous-delivery.md).

---

## 9. Funcionamiento del pipeline CI/CD

### 9.1 Flujo de ramas

```text
feature/HU-xx-*  ──PR (1 aprobación, squash)──▶  dev  ──PR de promoción (Product Owner)──▶  main  ──▶  tag vX.Y.Z
```

- Los rulesets `protect-dev` y `protect-main` exigen pull request y una aprobación de un integrante distinto del autor, y descartan las aprobaciones obsoletas.
- Los commits siguen Conventional Commits con el pie `Refs: PI-xx`. El workflow `.github/workflows/validate-pr-commits.yml` valida los commits del PR.
- Los webhooks de GitHub llegan a `/github-webhook/` por el relay smee.io; el escaneo cada 10 minutos sirve de respaldo. El job descubre ramas y PR; los PR se construyen sobre el *merge* con su rama base.

### 9.2 Etapas y condiciones

| Etapa | Qué hace | PR | `feature/*` | `dev` | `main` |
|:---|:---|:---:|:---:|:---:|:---:|
| Checkout | Clona el commit y la rama base | ✔ | ✔ | ✔ | ✔ |
| Detect changes | `ci/scripts/changed-units.sh` + `ci/units.conf`: solo las unidades modificadas. Un cambio en la raíz o en `ci/` reconstruye todo; uno solo en `docs/` o `infra/` no construye nada. | ✔ | ✔ | ✔ | ✔ |
| Build | `./gradlew assemble` de los servicios afectados | ✔ | ✔ | ✔ | ✔ |
| Test | `./gradlew test` + JaCoCo; publica JUnit y cobertura | ✔ | ✔ | ✔ | ✔ |
| Integration Test | `integrationTest` (Testcontainers) de los servicios con `@Tag("integration")` | ✔ | ✔ | ✔ | ✔ |
| Analysis | SonarQube con quality gate **bloqueante** (`auth`, `identity`, `promotion`, `form` y `gateway`) | ✔ | ✔ | ✔ | ✔ |
| Package | Imagen Docker con etiqueta inmutable `<semver>-ci.<build>.<sha7>` | ✔ | ✔ | ✔ | ✔ |
| Publish | Push a Nexus con `nexus-publisher` | — | — | ✔ | ✔ |
| Deploy Dev | `cgDeploy` por SSH a la EC2 de dev | — | — | ✔ | — |
| E2E on DEV | Playwright sobre dev (bloquea la promoción) | — | — | ✔ | — |
| Deploy Stage | `cgDeploy` a stage | — | — | — | ✔ |
| E2E Tests | Playwright sobre stage (`run-env.sh stage`) | — | — | — | ✔ |
| Approve Prod | `input` manual de 30 min, solo para `CG_PROD_APPROVERS` | — | — | — | ✔ si `CG_ENABLE_PROD_RELEASE=true` |
| Deploy Prod | `cgDeploy` a prod tras la aprobación | — | — | — | ✔ si `CG_ENABLE_PROD_RELEASE=true` |

Además de la rama, cada etapa tiene condiciones propias:
- las etapas de construcción solo corren si hay unidades afectadas;
- Analysis requiere `SONAR_HOST_URL`;
- Publish y los despliegues requieren `NEXUS_REGISTRY` y que el build no sea un PR.

Cuando una etapa se omite, Jenkins la muestra en blanco: no significa que haya fallado. Al terminar, el pipeline elimina las imágenes Docker locales con más de 24 horas y limpia el workspace.

### 9.3 Evidencia de funcionamiento

La ejecución exitosa más reciente de `dev` es el **build #37** (`/job/circleguard/job/dev/37/`). En ella terminaron en verde Checkout, Detect changes, Build, Test, Integration Test, Analysis, Package, Publish, **Deploy Dev** y **E2E on DEV**, con **195 pruebas aprobadas** y ninguna fallida ni omitida en el resumen de Jenkins. Las etapas de `main` (Deploy Stage, E2E Tests, Approve Prod y Deploy Prod) no corresponden a esa rama: **el build #37 no prueba los despliegues a stage ni a prod.** Cada build publica los resultados JUnit, los informes de cobertura y el informe HTML «HU-07 Playwright E2E».

### 9.4 Notificaciones

El estado de cada build se publica como *commit status* en GitHub y se ve en los PR y en el historial; lo hace el plugin GitHub Branch Source, con las credenciales de GitHub. `NOTIFY_WEBHOOK_URL` se provisiona como variable global para avisos compatibles con Slack, pero en la versión actual de la Shared Library no hay ninguna etapa que la use (ver 11.2).

---

## 10. Despliegues, validación y rollback

### 10.1 Qué hace un despliegue automatizado

1. `cgDeploy` comprueba la conectividad SSH (puerto 22) y copia `compose.base.yaml`, `compose.<env>.yaml` y `ci/deploy/deploy-remote.sh` a la EC2.
2. Después, `deploy-remote.sh` actúa en la propia EC2:
   - bloquea los despliegues concurrentes del mismo ambiente;
   - lee el `APP_VERSION` actual de `/opt/circleguard/environments/.env` y prepara una copia candidata con la versión nueva;
   - valida esa configuración y descarga de Nexus **solo** las imágenes de la aplicación (`auth`, `identity`, `promotion`, `form`, `gateway` y `web`), sin tocar las bases de datos;
   - aplica la versión con `docker compose up -d --no-build --wait` y espera los healthchecks (máximo 10 minutos);
   - si el arranque falla, **restaura automáticamente** el `.env` anterior y la versión previa; si la restauración también falla, deja el mensaje `CRITICAL: rollback failed`.
3. Nunca se compila en las EC2.

### 10.2 Verificación (solo lectura)

```bash
bash infra/status.sh                                  # estado e IP de las seis instancias
bash infra/bootstrap-verify.sh                        # Jenkins healthy, SonarQube UP, Nexus 200, registro 401
bash infra/environments/verify-env.sh dev             # compose ps, healthchecks, HTTP del cliente web y digests
bash infra/environments/verify-env.sh stage
bash infra/environments/verify-env.sh prod
```

`verify-env.sh` termina en `PASS` cuando:
- las seis aplicaciones están `healthy`;
- el cliente web responde por HTTP;
- se reporta el digest de cada imagen. Con los digests se puede comprobar que dev, stage y prod ejecutan exactamente la misma imagen.

Que el registro de Nexus responda **HTTP 401** sin autenticación es el comportamiento esperado. El cliente web escucha en `127.0.0.1:80` dentro de cada EC2, así que para revisarlo desde un navegador hace falta un túnel SSH:

```bash
ssh -i "$CIRCLEGUARD_SSH_KEY" -L 8780:127.0.0.1:80 ubuntu@<ip-publica-dev>
# luego abrir http://127.0.0.1:8780
```

### 10.3 Despliegue manual de un ambiente (HU-02)

`infra/environments/create-env.sh <env>` genera una sola vez el archivo privado `.env.<env>`, con modo 0600 y fuera de Git; antes de usarlo hay que definir en él `REGISTRY` y `APP_VERSION`. A partir de ahí:

```bash
bash infra/environments/validate.sh dev     # valida Compose y variables, sin AWS
bash infra/environments/deploy-env.sh dev   # despliega en la EC2 encendida; no sobrescribe un .env remoto distinto
bash infra/environments/verify-env.sh dev
```

### 10.4 Rollback

- **Automático:** viene integrado en cada despliegue del pipeline (10.1).
- **Manual a una versión anterior:** se usa el mismo mecanismo que `cgDeploy`. El script no queda instalado en la EC2 (`cgDeploy` lo copia a un temporal y lo elimina), así que se copia desde el repo y se invoca con `bash` como root; los argumentos son `dev|stage|prod` y una etiqueta que exista en Nexus (por ejemplo, la de un build anterior en verde). Usa `/opt/circleguard/environments/.env`, `compose.base.yaml` y `compose.<env>.yaml` ya presentes en la EC2, y vuelve a validar, descargar y esperar los healthchecks antes de dar el cambio por terminado:

```bash
scp -i "$CIRCLEGUARD_SSH_KEY" ci/deploy/deploy-remote.sh ubuntu@<ip-publica-env>:/tmp/deploy-remote.sh
ssh -i "$CIRCLEGUARD_SSH_KEY" ubuntu@<ip-publica-env> \
  'sudo bash /tmp/deploy-remote.sh <env> <version-anterior>; rc=$?; rm -f /tmp/deploy-remote.sh; exit $rc'
bash infra/environments/verify-env.sh <env>
```

### 10.5 Producción

Un despliegue a `prod` solo procede cuando:
- la **misma versión** se desplegó en stage y pasó E2E Tests;
- existe una **autorización explícita** de un usuario de `CG_PROD_APPROVERS` en el paso Approve Prod.

`CG_ENABLE_PROD_RELEASE` debe permanecer desactivada y activarse solo para un release autorizado. Sin aprobación en 30 minutos, el build queda `ABORTED` y prod no cambia.

### 10.6 Release

```bash
git switch main && git pull origin main
bash infra/release/version.sh                    # siguiente versión SemVer desde Conventional Commits
JIRA_KEY=PI-xx bash infra/release/release.sh     # antepone release notes a CHANGELOG.md, commit y tag vX.Y.Z
```

`release.sh` exige estar en `main` con el árbol limpio, y crea un commit sobre `main` antes del tag. Como las protecciones de `main` prohíben el push directo, **coordine con el Product Owner** cómo integrar ese commit; las alternativas se describen en la sección 11.2. Las imágenes de un release se construyen con `infra/release/build-images.sh X.Y.Z [--push]`, con `REGISTRY`, `NEXUS_USER` y `NEXUS_PASSWORD` definidos en el entorno.

---

## 11. Solución de problemas y limitaciones

### 11.1 Diagnóstico frecuente

Empiece siempre por las comprobaciones de solo lectura. No borre volúmenes, no muestre secretos y no reinicie servidores sin coordinar con el equipo.

| Síntoma | Diagnóstico | Acción recomendada |
|:---|:---|:---|
| Jenkins no responde | `bash infra/status.sh`: la instancia está detenida o cambió su IP | Encenderla con autorización (`power.sh start jenkins`) y usar la IP nueva; luego `bootstrap-verify.sh`. |
| `build-agent` desconectado | En la EC2 de Jenkins: `sudo docker ps --filter name=circleguard-build-agent` y `sudo docker logs --tail 50 circleguard-build-agent` | Volver a ejecutar `bash infra/bootstrap-ci.sh`, que es idempotente y conserva el secreto del agente. |
| No se descubre una rama o un PR | Revisar *Scan Repository Log* y que la credencial `github-scan` exista; comprobar las entregas del webhook en GitHub y el contenedor `circleguard-webhook-relay` | *Scan Repository Now*; renovar `GITHUB_TOKEN` o `SMEE_URL` con `bootstrap-ci.sh`. |
| Falla la conexión a SonarQube o a Nexus | `infra/status.sh` (¿instancia encendida?), `bootstrap-verify.sh`; comprobar que `SONAR_HOST_URL` y `NEXUS_REGISTRY` usan **IP privadas** | Encender el servicio; actualizar las variables con `bootstrap-ci.sh` si cambiaron. |
| Poco espacio en Jenkins | `df -h` y `sudo docker system df` en la EC2 | `sudo docker image prune -f` y `sudo docker builder prune -f` (no afectan volúmenes). **Nunca** `docker volume prune`. |
| Testcontainers falla por recursos | Log de Integration Test: falta de memoria o de disco, o contenedores inaccesibles | Liberar espacio (fila anterior); definir `TC_HOST_OVERRIDE` si el agente no alcanza los contenedores. |
| Falla Docker Compose en un ambiente | `verify-env.sh <env>`; `sudo docker compose -p circleguard-<env> ... ps` y los logs del servicio | Revisar el `.env` privado, la memoria (al menos 8 GiB) y el acceso del Docker Engine al registro (`insecure-registries`). |
| E2E falla por conectividad o CORS | Log de la etapa: el túnel SSH usa los puertos 8780 (dev) y 8781 (stage); `AUTH_CORS_ALLOWED_ORIGINS` incluye por defecto `http://127.0.0.1:8780` | `compose.base.yaml` pasa `AUTH_CORS_ALLOWED_ORIGINS` al servicio `auth` como `APP_CORS_ALLOWED_ORIGINS`, y `compose.stage.yaml` no lo sobrescribe. Para stage, definir `AUTH_CORS_ALLOWED_ORIGINS=http://localhost:8081,http://localhost:8080,http://127.0.0.1:8781` en `infra/environments/.env.stage` y con el mismo contenido en `/opt/circleguard/environments/.env` de la EC2 de stage (`deploy-env.sh` rechaza archivos distintos), y redesplegar con `bash infra/environments/deploy-env.sh stage` para que `auth` se recree; comprobar las credenciales `circleguard-stage-host` y `circleguard-stage-ssh`. |
| Ambiente EC2 detenido | `infra/status.sh` o `environments/preflight-ec2.sh` | Encenderlo con autorización y **actualizar `EC2_<ENV>_HOST`** en Jenkins (sección 8.4), porque la IP cambia. |
| Deploy falla por configuración | Mensajes `cgDeploy: no host for ...`, `SSH connectivity check failed` o `Environment .env not found` | Configurar `EC2_*_HOST` y `ec2-ssh-key` (8.4); ejecutar `deploy-env.sh <env>` una vez para crear el `.env` remoto. |

### 11.2 Limitaciones conocidas

- **Configuración manual:** `CG_PROD_APPROVERS`, `CG_ENABLE_PROD_RELEASE` y las ocho credenciales E2E (`circleguard-*`) no se crean desde los scripts.
- **Variables que `bootstrap-ci.sh` no reenvía:** `EC2_*_HOST`, `EC2_SSH_KEY_B64` y `NOTIFY_WEBHOOK_URL` deben enviarse a `ci-remote.sh` (8.4). Además, las IP públicas cambian con cada reinicio.
- **Notificaciones:** `NOTIFY_WEBHOOK_URL` está provisionada, pero en la versión actual ninguna etapa la consume. La notificación efectiva es el *commit status* en GitHub.
- **Rollback:** el rollback automático está integrado en el despliegue. No existe un job de rollback dedicado en Jenkins: el rollback manual se hace con `deploy-remote.sh` (10.4).
- **Release:** `release.sh` crea el commit del CHANGELOG directamente sobre `main`, en conflicto con los rulesets. Hay dos alternativas: hacer la integración mediante PR o crear el tag después de fusionar el CHANGELOG. `CHANGELOG.md` todavía no contiene releases publicados.
- **Seguridad del registro:** el registro de Nexus usa HTTP dentro de la VPC, con `insecure-registries` en las EC2. Queda pendiente endurecerlo con TLS.
- **Agente de build:** usa el socket Docker del host; solo construye código del repositorio y no debe ejecutar PR de forks.
- **Recursos y costos:**
  - el almacenamiento limitado de Jenkins exige mantenimiento periódico de imágenes y caché;
  - apagar las EC2 para ahorrar costos añade tiempo de arranque y verificación.
- **Cliente web:** `web` solo se empaqueta y se valida con la suite E2E; sus pruebas Jest corren fuera del pipeline.
- **Cumplimiento normativo:** FERPA, la privacidad y la disponibilidad descritas en este README son objetivos de diseño del producto original. No se han auditado ni certificado en este proyecto.

---

## 12. Referencias

| Tema | Ruta |
|:---|:---|
| Manual de infraestructura (TEC-04, HU-01, HU-02) | [`infra/README.md`](infra/README.md) |
| Costos y apagado | [`infra/docs/costs.md`](infra/docs/costs.md) |
| Pipeline CI (HU-04) | [`docs/operaciones/hu-04-pipeline-ci.md`](docs/operaciones/hu-04-pipeline-ci.md) |
| Quality gate (HU-05) | [`docs/operaciones/hu-05-quality-gate.md`](docs/operaciones/hu-05-quality-gate.md) |
| Entrega continua (HU-08) | [`docs/operaciones/hu-08-continuous-delivery.md`](docs/operaciones/hu-08-continuous-delivery.md) |
| Hallazgos técnicos | [`docs/operaciones/hallazgos_tecnicos.md`](docs/operaciones/hallazgos_tecnicos.md) |
| Marco Scrum, branching, backlog, ceremonias e informe | [`docs/agil/`](docs/agil/) |
| Gestión de cambios | [`docs/agil/06_Gestion_Cambios_CircleGuard.md`](docs/agil/06_Gestion_Cambios_CircleGuard.md) |
| Release notes | [`CHANGELOG.md`](CHANGELOG.md) |
| Uso de IA generativa | [`IAG_REGISTRO.md`](IAG_REGISTRO.md) |

---

## Privacy & Compliance (product design principles)

> Principios de diseño del producto original. No han sido auditados en el marco de este proyecto.

- **FERPA Compliance**: Student identities are never stored in the contact graph.
- **Right to be Forgotten**: Users can trigger complete data purging via the Identity Vault.
- **Temporal Privacy**: All contact edges are automatically purged after 14 days.
