# infra/ - AWS provisioning (TEC-04 / E1.2)

Idempotent Bash scripts that create the CircleGuard servers on AWS (default VPC,
`us-east-1`): **jenkins, sonarqube, nexus** (CI/CD) and **dev, stage, prod**
(one server per environment). Nothing is configured by hand; re-running a
script only creates what is missing. No credentials or keys live in this repo.

## Topology

| Security group | Servers | Inbound |
|:---|:---|:---|
| `circleguard-sg-cicd` | jenkins, sonarqube, nexus | 22, 8080 (Jenkins), 9000 (SonarQube), 8081/8082 (Nexus) from the admin IP; 8081/8082 from the env SGs (image/artifact pull) |
| `circleguard-sg-dev/stage/prod` | one server each | 22 from admin IP and from the CI/CD SG; 80 public (web client); service ports 8180, 8082-8088 from CI/CD SG and admin IP |

Environment SGs never reference each other, so **traffic between dev, stage and
prod is denied**. SSH is key-only (Ubuntu 24.04 default) and never open to
`0.0.0.0/0`. Servers use IMDSv2 and encrypted-in-transit package sources.
`c7i-flex.large` (CI/CD, 4 GiB) and `t3.small` (environments, 2 GiB + swap) are a first estimate; resize if Neo4j + Kafka need more.

## Prerequisites

* AWS CLI v2 and a **personal IAM access key** (never pasted in chat or git):
  `aws configure` (region `us-east-1`). The IAM user needs EC2, SSM (read) and Budgets permissions.
* Bash (WSL/Linux/macOS), `curl`.

## Usage (in order)

```bash
infra/bootstrap-keypair.sh          # SSH key pair; .pem goes to ~/.ssh (chmod 400)
infra/bootstrap-network.sh          # security groups and rules
infra/bootstrap-instances.sh        # 6 servers, Docker installed via user-data
infra/create-budget.sh you@mail.com 50
infra/verify.sh                     # checks the TEC-04 acceptance criteria
infra/status.sh                     # states and IPs
ssh -i ~/.ssh/circleguard-key.pem ubuntu@<public-ip>
```

Change sizes, disks or the key name in `config.env` (or override via env vars).
Costs and shutdown: see `docs/costs.md`.

## Acceptance criteria (Jira PI-4)

| Criterion | Evidence |
|:---|:---|
| CI/CD and 3 environment servers exist | `verify.sh`, `status.sh` |
| Traffic between environments blocked | `verify.sh` (no cross-env SG references) |
| SSH by key, no key in the repo | `.gitignore` (`*.pem`), `verify.sh` |
| Cost estimate and shutdown procedure | `docs/costs.md`, `power.sh`, `teardown.sh` |





































































































































































































## HU-02 — Docker Compose environments (PI-7 / Sprint 1)

### Objetivo y alcance

Se despliegan **dev, stage y prod** sobre tres EC2 independientes reutilizadas de TEC-04. La pila por ambiente contiene los cinco microservicios núcleo (`auth`, `identity`, `promotion`, `form`, `gateway`), el cliente `web` y seis servicios de middleware (`postgres`, `neo4j`, `zookeeper`, `kafka`, `redis`, `openldap`): **12 contenedores por ambiente**. Los otros tres microservicios del monorepo no forman parte de HU-02.

Se utilizan los archivos `infra/environments/compose.base.yaml`, `compose.dev.yaml`, `compose.stage.yaml`, `compose.prod.yaml` e `init-db.sql`. Los scripts `create-env.sh`, `validate.sh`, `deploy-env.sh`, `verify-env.sh`, `preflight-ec2.sh` permiten configuración privada, validación local, despliegue remoto y verificación reproducible. El despliegue utiliza `docker compose pull` y `up -d --no-build`; **nunca recompila en las EC2**.

### Configuración y seguridad

Cada ambiente requiere su archivo privado `.env.dev`, `.env.stage` o `.env.prod`, creado con `create-env.sh` y excluido del repositorio. Los valores `REGISTRY` y `APP_VERSION` son configurados localmente; para la ejecución documentada se utilizó el registro privado Nexus `172.31.5.84:8082` y las imágenes de prueba `1.0.0`. No hay que publicar valores secretos, contraseñas ni archivos `.pem`. En la EC2 cada `.env` se guarda con permisos restringidos en `/opt/circleguard/environments/.env`; el script protege contra sobreescritura de secretos divergentes.

Los tres ambientes usan redes/grupos de seguridad independientes creados en TEC-04. El frontend enlaza `127.0.0.1:80` en la instancia, por lo que **no queda expuesto directamente a Internet**; la prueba de HTTP se realiza de forma local por SSH. La credencial `cg-reader` de Nexus se introduce sin mostrarla. Cada instancia dispone de **8 GiB RAM (`m7i-flex.large`)** tras la ampliación documentada en `infra/docs/costs.md`.

**Limitación de seguridad identificada:** el conector Docker Registry de Nexus usa **HTTP** en `172.31.5.84:8082`. Durante esta ejecución se configuró la excepción específica de Docker `insecure-registries` en las tres EC2 de ambiente para ese endpoint privado. Esa conexión **no usa TLS**: queda pendiente de endurecimiento mediante HTTPS y certificado de confianza, o validación formal de la excepción por el responsable de infraestructura. No se debe publicar el puerto de registro abiertamente en Internet.

### Uso local (sin iniciar AWS)

```bash
# Requiere archivos .env.* privados existentes y variables de imagen definidas
bash infra/environments/validate.sh dev
bash infra/environments/validate.sh stage
bash infra/environments/validate.sh prod

# Sintaxis de scripts Bash
for f in infra/environments/*.sh; do bash -n "$f" || exit 1; done
```

### Despliegue remoto (opcional; genera costos)

Requisitos: AWS CLI/perfil IAM autorizado, llave privada SSH en el equipo (nunca en Git), instancias EC2 de 8 GiB encendidas, Nexus disponible y conectividad del Docker Engine al registro autorizada. Antes de iniciar o detener servidores, coordinar con TEC-04 y el equipo.

```bash
export AWS_PROFILE='<perfil-autorizado>'
export CIRCLEGUARD_SSH_KEY="$HOME/.ssh/circleguard-key.pem"
bash infra/status.sh

# Ejecutar únicamente sobre el ambiente autorizado y encendido
bash infra/environments/deploy-env.sh dev
bash infra/environments/verify-env.sh dev

# Análogo para stage y prod, sin volver a construir imágenes
bash infra/environments/deploy-env.sh stage
bash infra/environments/verify-env.sh stage
bash infra/environments/deploy-env.sh prod
bash infra/environments/verify-env.sh prod
```

No repetir estas operaciones solo para revisar la HU si las instancias están detenidas: usar las evidencias adjuntas a Jira PI-7. El arranque automático y la promoción desde Jenkins pertenecen a historias posteriores, no a HU-02.

### Validación efectuada en AWS — 8 de noviembre de 2026

| Evidencia | Resultado observado |
|:---|:---|
| Archivos Compose y variables de dev, stage, prod | `validate.sh` PASS en los tres |
| Servicios en AWS | 12 contenedores desplegados por ambiente; las seis aplicaciones `healthy` |
| Frontend y Actuator | `verify-env.sh`: HTTP frontend OK, cinco probes Actuator y checks saludables; `PASS` evidenciado en dev y prod, con registro de stage disponible en evidencias Jira |
| Artefactos inmutables | Los seis digests SHA-256 de las imágenes `1.0.0` coincidieron entre dev, stage y prod; no hubo compilación en EC2 |
| Persistencia | Se verificó la presencia de seis volúmenes Docker de datos en dev; **no se ejecutó prueba de escritura/reinicio/lectura** |
| Secretos | `git ls-files 'infra/environments/.env.*'` devolvió solo `.env.example`; archivos privados excluidos de Git |
| Incidencia resuelta | Neo4j 5.26 rechazaba `NEO4J_PASSWORD` como configuración; se usa `NEO4J_AUTH` y healthcheck de `cypher-shell` basado en esa variable |

**Trazabilidad de versión:** `1.0.0` fue una etiqueta de imágenes construidas para validación desde la rama HU-02 (commit base `302e05b`); no implica la creación de un release oficial de HU-03 ni la existencia de un tag Git `v1.0.0`.

### Apagado y costos

```bash
bash infra/status.sh
# Con autorización y sin otros compañeros usando estas instancias:
bash infra/power.sh stop dev stage prod nexus
bash infra/status.sh
```

No usar `docker compose down -v`, `docker volume rm`, `docker volume prune` ni `infra/teardown.sh`. Detener EC2 evita seguir consumiendo cómputo, pero no elimina el costo de EBS. Ver **estimación inicial TEC-04 y actualización HU-02** en `infra/docs/costs.md`.

### Jira y evidencias

- **Product Backlog:** HU-02 — Ambientes con Docker Compose.
- **Jira:** PI-7; **Sprint:** 1; **Épica:** E2; **Entregables:** E1.2 y E1.3.
- **Evidencias:** archivo ZIP de pruebas y capturas adjuntas en Jira, incluyendo salidas `AWS_dev.txt`, `AWS_stage.txt`, `AWS_prod.txt`, registros de despliegue, Nexus y comparación de digests.
- **Código y documentación:** `infra/environments/`, `infra/README.md`, `infra/docs/costs.md`.
