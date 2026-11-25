# Bitácora de problemas y soluciones: Hideki Tamura Hernández

**Proyecto:** CircleGuard, Parte 2 (Sprint 2, del 9 al 22 de noviembre de 2026)  
**Rol:** Desarrollador  
**Historias trabajadas:** HU-17 (PI-26), HU-18 (PI-27), HU-19 (PI-28), HU-22 (PI-31) y TEC-12 (PI-34)

Esta bitácora es una guía de los problemas que me encontré en esta fase y de cómo los resolví. La escribo para que, si a alguien del equipo le pasa lo mismo, pueda ir directo a la solución sin perder el tiempo que perdí yo.

## Cómo usé la IA

Usé dos asistentes de IA:

| Herramienta | Para qué la usé |
| --- | --- |
| Gemini | Revisar y corregir manifiestos de Kubernetes en HU-19; generar la primera guía de HU-18 y redactar los PRs de HU-19, HU-18, HU-22 y TEC-12; resolver errores de Conventional Commits, Git Bash/`PATH` en Windows y pruebas offline en `pytest`; estructurar `rollback.sh`, su documentación, su suite `test_k8s_rollback.py` y el documento de cierre ágil de TEC-12. |
| Claude | Evaluar la guía inicial de HU-18 contra el código real del repositorio, corregirla para k3s y entender errores concretos: el compose, `kubectl`, las rutas de Git Bash y las variables de entorno de los servicios. |

Los usé para entender por qué pasaba cada error y qué alternativas tenía, de forma parecida a como uno le pregunta a un monitor o a un compañero que sabe más del tema.

Lo que **no** le dejé a la IA:

- **Decidir cómo se reparte el trabajo.** Acordé con mi compañero que yo validaba en local y que él validaba en AWS, porque él es quien enciende las instancias y administra los clústeres.
- **Tocar ambientes compartidos.** No desplegué nada en AWS por mi cuenta; ese paso quedó en manos de quien administra los ambientes.
- **Dar por bueno un resultado sin comprobarlo.** Cada archivo se ejecutó o se probó (`promtool`, `test_grafana_dashboards.py`, `test_k8s_rollback.py`, `validate.py`, `gradlew test`) antes de darlo por correcto.

Este uso sigue el **Nivel 3: colaboración con IAG** que el equipo declaró en `IAG_REGISTRO.md`.

---

## 1. HU-17: Alertas críticas sobre métricas de Prometheus (PI-26, PR #70)

**Qué pide la historia.** Exponer métricas técnicas y de negocio en los 8 microservicios, desplegar Prometheus y Alertmanager por ambiente, y definir alertas críticas verificables.

### Problema 1.1: descubrimiento de targets por Service vs. Pod y acceso a `/actuator/prometheus`

**Qué pasó.** Al plantear el scrapeo de métricas en Kubernetes, apuntar a los `Service` de los microservicios generaba lecturas inconsistentes cuando hay más de una réplica (como en `prod`, con 2 réplicas por servicio). Además, el servicio `identity` bloqueaba la lectura de `/actuator/prometheus`.

**Por qué.** Un `Service` balancea cada petición de Prometheus entre distintas réplicas, mezclando contadores y rompiendo funciones como `rate()`. En `identity`, `SecurityConfig` exigía autenticación para los endpoints de Actuator.

**Cómo se resolvió.** Se configuró Prometheus con `kubernetes_sd_configs` (rol `pod`, restringido a su propio namespace con un `Role` de mínimo privilegio `get/list/watch`), filtrando solo los 8 servicios Spring Boot (dejando fuera `web` y el middleware) y etiquetando por `service`, `application` y `pod`. En `identity`, se habilitó el acceso sin autenticación a `/actuator/prometheus` en `SecurityConfig`. El despliegue quedó encapsulado en `infra/k8s/observability.sh` con la URL del webhook en el Secret `alertmanager-webhook`.

**Lección.** En Kubernetes, Prometheus debe descubrir pods individuales y no Services para mantener consistencia en las métricas, y cada servicio con seguridad activa requiere revisar sus reglas de acceso a Actuator.

### Problema 1.2: cómo disparar alertas críticas sin tumbar el pod ni recibir falsos 401

**Qué pasó.** Al diseñar las pruebas de falla real para las alertas, no fue posible provocar `HighLatencyP95` de forma limpia en el clúster, y al probar `HighErrorRate` y `CircuitBreakerOpen` contra `auth`, peticiones sin credenciales válidas no disparaban la alerta.

**Por qué.** El `/actuator/health` de los servicios incluye la base de datos: si se apaga PostgreSQL para inducir lentitud, Kubernetes saca el pod de servicio y lo reinicia por `livenessProbe` antes de que se cumplan los 3 minutos de `HighLatencyP95`. Por otro lado, `auth` valida contra LDAP antes de llamar a `identity`; con credenciales inválidas devuelve `401`, no `503`, así que ni sube la tasa 5xx ni se abre el circuit breaker.

**Cómo se resolvió.** Se dejaron 3 alertas críticas con prueba de falla real (`ServiceDown` mediante `fail-service-down.sh`, y `HighErrorRate` + `CircuitBreakerOpen` mediante `fail-circuit-error-rate.sh` usando una cuenta LDAP válida en un Secret temporal que se borra al terminar), mientras `HighLatencyP95` quedó como `warning` cubierta con pruebas unitarias offline vía `promtool test rules`. También se documentó el impacto de memoria (~640 MiB adicionales en `dev`) y el carácter efímero de la retención de 7 días sin volumen persistente.

**Lección.** Las pruebas de alertas en Kubernetes deben diseñarse teniendo en cuenta las sondas de salud (`liveness`/`readiness`) y el flujo real de autenticación del servicio, y complementarse con pruebas unitarias de reglas en `promtool`.

### Resultado de la HU-17

Se habilitaron `spring-boot-starter-actuator` y `micrometer-registry-prometheus` en los 8 servicios, se instrumentaron las métricas de negocio (`circleguard_promotions_total`, `circleguard_checkins_total`, `circleguard_containment_duration_seconds`) junto con `resilience4j_circuitbreaker_state`, se configuraron Prometheus y Alertmanager en `infra/k8s/observability.sh` y se validaron las reglas con `promtool test rules` y `./gradlew test`. Integrado en `dev` mediante el PR #70 y documentado en `docs/operaciones/hu-17-alertas-prometheus.md` (despliegue final en clúster real coordinado con AWS).

---

## 2. HU-18: Monitoreo centralizado en Grafana (PI-27, PR #75)

**Qué pide la historia.** Dashboards técnicos (uno por servicio) y de negocio en Grafana, los logs de los 8 servicios en Loki filtrables por servicio y nivel, y todo versionado en `observability/grafana`.

### Problema 2.1: guía inicial pensada para Docker y no alineada con las reglas del proyecto

**Qué pasó.** La primera guía proponía Promtail leyendo `docker.sock`, la clave `GF_SECURITY_ADMIN_PASSWORD=admin` en texto plano, un único dashboard con menú desplegable exportado a mano, un regex de nivel propenso a falsos positivos y un script nuevo (`deploy-logging.sh`).

**Por qué.** Los ambientes reales corren en k3s (containerd, sin `docker.sock`); las contraseñas en texto plano violan HU-02 y el escaneo de Trivy (HU-20); el criterio exigía un dashboard por servicio; los stack traces de Spring Boot ocupan varias líneas; y ya existía `infra/k8s/observability.sh` con selección segura de clúster (`select_cluster` y `kc`).

**Cómo se resolvió.** Se rehízo el diseño para k3s: `loki.yaml`, `promtail.yaml` (DaemonSet con `Role` de mínimo privilegio, etapa `cri`, `multiline`, regex anclada para `level` y `runAsUser: 0` documentado para leer `/var/log/pods`) y `grafana.yaml` (credenciales desde el Secret `grafana-admin`). Se creó `generate_dashboards.py` para generar los 9 JSON con `uid` fijos (`prometheus`, `loki`) verificados por `ci/tests/test_grafana_dashboards.py` (5 pruebas en verde), y todo se integró dentro de `infra/k8s/observability.sh`.

**Lección.** Toda guía generada por IA debe contrastarse contra la arquitectura real del repositorio y reutilizar los scripts y controles de seguridad existentes.

### Problema 2.2: conflictos en la validación local (`compose.local.yaml`, Git Bash y `bootRun`)

**Qué pasó.** Al mezclar bloques en `observability/compose.local.yaml` apareció `additional properties 'grafana' not allowed` y un contenedor `promtail` huérfano; al validar configuraciones con `docker run`, Git Bash transformó `/c` en `C:/`; y al arrancar servicios con `bootRun` fallaron por `WeakKeyException` y falta de contraseña de PostgreSQL.

**Por qué.** La indentación del YAML quedó desalineada y conservaba el bloque `promtail` antiguo; Git Bash convierte automáticamente rutas que empiezan con `/`; y los servicios locales no tenían exportadas las variables de entorno de desarrollo (`JWT_SECRET`, `QR_SECRET` y contraseñas de BD/Neo4j/LDAP).

**Cómo se resolvió.** Se limpió `compose.local.yaml` (`docker compose ... config` y `up -d --remove-orphans`), se agregó `promtail-local.yaml` para leer logs locales en `.local-logs/`, se validaron Loki y Promtail usando `MSYS_NO_PATHCONV=1` con `$(pwd -W)`, y se definieron las variables de desarrollo por terminal para `bootRun` (más `GRAFANA_ADMIN_PASSWORD` para Grafana).

**Lección.** Reemplazar bloques YAML completos evita errores de indentación; en Git Bash conviene usar `MSYS_NO_PATHCONV=1` con Docker y leer siempre la línea `Caused by:` de los errores de Spring Boot.

### Problema 2.3: sin contexto `kubectl` ni acceso a AWS en local

**Qué pasó.** `kubectl config get-contexts` devolvió vacío al intentar probar `observability.sh`, y al solicitar acceso al clúster envié inicialmente un fragmento de texto en lugar de la clave SSH pública (`.pub`).

**Por qué.** Un `kubeconfig` depende de que el clúster ya esté aprovisionado y exportado, y la clave pública debe ser el contenido completo de `~/.ssh/id_ed25519.pub`.

**Cómo se resolvió.** Como otro integrante ya trabajaba sobre los clústeres en AWS, acordamos dividir la validación: yo verifiqué toda la implementación y el stack en local, y él ejecutó `observability.sh dev` para las capturas en el ambiente real.

**Lección.** Verificar que siempre se envíe el archivo `.pub` (nunca la llave privada) y coordinar la validación en ambientes compartidos para evitar conflictos.

### Problema 2.4: fallo de Conventional Commits y build abortado en Jenkins

**Qué pasó.** En el PR #75 falló `validate-pr-commits.yml` por un commit anterior con asunto no imperativo (`fix(observability): loki, promtail and grafana modified`), y posteriormente GitHub mostró `continuous-integration/jenkins/pr-merge — The build of this commit was aborted`.

**Por qué.** GitHub Actions valida todos los commits del rango `origin/dev..HEAD` (no solo el último), y Jenkins aborta el build cuando un `force-with-lease` pisa una ejecución en curso o se reinicia la instancia EC2.

**Cómo se resolvió.** Se unificaron los commits de la rama con `git reset --soft $(git merge-base HEAD origin/dev)`, se hizo un único commit válido (`feat(observability): add grafana dashboards and loki logging` + `Refs: PI-27`), se subió con `--force-with-lease` y se relanzó el build en Jenkins.

**Lección.** Ante fallos de Conventional Commits en ramas con varios commits, conviene unificar o reescribir el historial antes de volver a subir; y ante un estado `aborted`, revisar el estado de Jenkins antes de asumir un error de código.

### Resultado de la HU-18

Se integraron Loki, Promtail y Grafana en `infra/k8s/observability.sh` y `observability/compose.local.yaml`, junto con los 9 dashboards versionados (`generate_dashboards.py`) y `ci/tests/test_grafana_dashboards.py` (5/5 en verde), `validate.py` en verde y PR #75 fusionado en `dev`. Despliegue y capturas finales en k3s coordinados con el administrador de AWS.

---

## 3. HU-19: Trazado distribuido con Jaeger (PI-28, PR #71)

**Qué pide la historia.** Instrumentar con OpenTelemetry los servicios del flujo asíncrono (`form`, `promotion` y `notification`), propagar el contexto de traza a través de Kafka y desplegar Jaeger para visualizar el recorrido completo en una sola traza.

### Problema 3.1: variable `OTEL_EXPORTER_OTLP_ENDPOINT` mal ubicada y mal escrita en los manifiestos k8s

**Qué pasó.** Al configurar el envío de trazas hacia Jaeger en `infra/k8s/base/apps/form.yaml`, agregué la variable al final del bloque `containers:` (debajo de `resources:`) y con el nombre `OTEL_EXPORTER_OTLP_ENDPNT`.

**Por qué.** Fuera de `env:` y al mismo nivel que `- name: form`, Kubernetes la habría interpretado como un segundo contenedor inválido; además, con el nombre mal escrito Spring Boot / OpenTelemetry la habría ignorado en silencio.

**Cómo se resolvió.** Se movió la variable dentro de `env:` debajo de `SPRING_KAFKA_BOOTSTRAP_SERVERS` con el nombre exacto `OTEL_EXPORTER_OTLP_ENDPOINT` y valor `"http://jaeger:4318/v1/traces"`, replicándola en `promotion.yaml` y `notification.yaml`. Se validó con `python infra/k8s/validate.py` (`OK: all environments consistent`) y pruebas unitarias con Gradle.

**Lección.** Revisar siempre la indentación de `env:` y el nombre exacto de las variables de telemetría, porque un error tipográfico suele fallar en silencio sin detener el arranque del pod.

### Resultado de la HU-19

Se instrumentaron `form`, `promotion` y `notification` con Micrometer Tracing + OpenTelemetry OTLP, propagación de contexto en Kafka (`observation-enabled: true`) e inyección de `traceId`/`spanId` en logs; se agregó Jaeger en `docker-compose.dev.yml` y `infra/k8s/base/jaeger.yaml`. Validado con `validate.py` y Gradle, e integrado en `dev` mediante el PR #71.

---

## 4. HU-22: Rollback en Kubernetes (PI-31, PR #76)

**Qué pide la historia.** Ejecutar un rollback en Kubernetes con evidencia, asegurar release notes por versión publicada y mantener un registro de cambios por ambiente.

### Problema 4.1: `kubectl` sin contexto `circleguard-dev` y errores de sintaxis en consola

**Qué pasó.** `kubectl --context circleguard-dev -n circleguard-dev rollout history deployment/auth` devolvió `error: context "circleguard-dev" does not exist`. Además, `; echo` en PowerShell pidió parámetros interactivos y copiar `<registro-nexus>` literalmente en Bash dio `syntax error near unexpected token '<'`.

**Por qué.** No había un `kubeconfig` local conectado al clúster de AWS (acordamos validar localmente para no generar conflictos). En PowerShell `echo` es alias de `Write-Output` y en Bash `< >` son operadores de redirección.

**Cómo se resolvió.** Se implementó `infra/k8s/rollback.sh` reutilizando `select_cluster` y `kc` (`infra/k8s/lib.sh`), el plan operativo `docs/operaciones/hu-22-rollback-k8s.md`, la bitácora por ambiente `docs/operaciones/registro-cambios-ambientes.md` y la suite offline `ci/tests/test_k8s_rollback.py` con un mock de `kubectl`.

**Lección.** No pegar marcadores `<...>` literalmente en consola y apoyarse en pruebas offline con mocks para validar scripts de infraestructura cuando el clúster real es compartido.

### Problema 4.2: fallos masivos de `pytest` en Windows por WSL `bash.EXE` y falta de `cygpath`

**Qué pasó.** Al correr `python -m pytest ci/tests/ -q` en PowerShell fallaron 45 pruebas con `RuntimeError: Git Bash cygpath is required on Windows` y errores de WSL (`execvpe(/bin/bash) failed`), además de `test_docs_and_changelog_exist` porque aún faltaba crear `docs/operaciones/registro-cambios-ambientes.md`.

**Por qué.** En PowerShell, Python resolvió `C:\WINDOWS\system32\bash.EXE` (WSL sin distribución instalada) antes que los binarios de Git Bash.

**Cómo se resolvió.** Se creó `docs/operaciones/registro-cambios-ambientes.md` y se corrieron las pruebas en **Git Bash** anteponiendo sus rutas al `PATH` (`export PATH="/usr/bin:/mingw64/bin:$PATH"`). Pasaron 7/7 en `test_k8s_rollback.py`, 118/120 en la suite completa (los 2 fallos restantes en `test_hpa_control.py` son previos y específicos de WSL en Windows) y `validate.py` en verde.

**Lección.** En Windows, ejecutar siempre las pruebas de scripts Bash desde Git Bash con `/usr/bin` al inicio del `PATH` y marcar los scripts como ejecutables en Git (`git update-index --add --chmod=+x`).

### Problema 4.3: clave de Jira equivocada en el commit del PR

**Qué pasó.** Hice el commit con `Refs: PI-XX`, luego lo cambié a `PI-38` y después verifiqué que la tarjeta real de HU-22 era `PI-31`.

**Por qué.** No confirmé el número exacto de la tarjeta en Jira antes de ejecutar el commit.

**Cómo se resolvió.** Se corrigió con `git commit --amend -m "feat(k8s): add kubernetes rollback script and change log" -m "Refs: PI-31"` y `git push --force-with-lease origin HEAD`, actualizando también la descripción del PR.

**Lección.** Confirmar siempre la clave real de Jira antes de hacer `git commit`.

### Resultado de la HU-22

Se integraron en `dev` (PR #76) el script `infra/k8s/rollback.sh`, el plan operativo `docs/operaciones/hu-22-rollback-k8s.md`, el registro por ambiente `docs/operaciones/registro-cambios-ambientes.md` y 7 pruebas automatizadas offline en `ci/tests/test_k8s_rollback.py` (7/7 en verde). La captura de ejecución final en k3s quedó coordinada con el despliegue en AWS.

---

## 5. TEC-12: Cierre ágil del Sprint 2 (PI-34, PR #82)

**Qué pide la tarea.** Documentar la planeación, la review, la retrospectiva y las lecciones aprendidas del Sprint 2, incluyendo los burndowns de los Sprints 1 y 2 y la verificación de las acciones de mejora del Sprint 1.

### Problema 5.1: consolidar la trazabilidad real del Sprint 2 y el cálculo de capacidad entre sprints

**Qué pasó.** Al estructurar el cierre del Sprint 2 (9 al 22 de noviembre de 2026) era necesario evaluar objetivamente las seis acciones de mejora del Sprint 1 y aclarar el significado de los valores de capacidad (`53 (94 %)` en Sprint 1 frente a `90 (recalculada)` en Sprint 2).

**Por qué.** Sin cruzar las fechas reales de integración en `dev` se pierde visibilidad de fases como el arrastre de estabilización del 9 y 10 de noviembre; y la capacidad del Sprint 2 se recalculó en TEC-07 usando la velocidad real medida (1,28 h efectivas/punto sobre 115,2 h efectivas = 90 puntos).

**Cómo se resolvió.** Se cruzó el historial real de commits fusionados en `dev` (9 al 22 de noviembre) con `07_Registro_Ceremonias_Sprints_0_1_CircleGuard.docx` para redactar `docs/agil/08_Registro_Ceremonias_Sprint_2_CircleGuard.docx` (Actas 7, 8 y 9, evaluación de las 6 acciones de mejora, comparación cuantitativa de Sprints 1 y 2, espacios para capturas de Jira y 5 lecciones aprendidas concretas), versionado en la rama `feature/TEC-12-cierre-agil-sprint-2`.

**Lección.** Cruzar el historial de commits y PRs con el tablero de Jira permite construir retrospectivas basadas en evidencia medible y no en percepciones.

### Resultado de la TEC-12

Documento `docs/agil/08_Registro_Ceremonias_Sprint_2_CircleGuard.docx` generado y versionado en `feature/TEC-12-cierre-agil-sprint-2` (PR #82), con actas de ceremonias, comparación de burndowns de Sprints 1 y 2, verificación de acciones de mejora y lecciones aprendidas concretas.

---

## 6. Buenas prácticas de seguridad

- **Credenciales fuera del repositorio.** La clave de Grafana (`grafana-admin`), el webhook de alertas (`alertmanager-webhook`) y las credenciales de pruebas LDAP viven en Secrets de Kubernetes o variables de entorno temporales; nada se versiona en Git.
- **Clúster siempre explícito.** Tanto `observability.sh` como `rollback.sh` reutilizan `select_cluster` y `kc` (`infra/k8s/lib.sh`) para fijar el contexto y rechazar contextos de otro ambiente.
- **Mínimo privilegio.** Prometheus y Promtail usan `Role` de solo lectura (`get/list/watch` de pods) limitado a su propio namespace; los puertos locales de observabilidad escuchan solo en `127.0.0.1`.
- **Solo la clave pública y cambios coordinados.** Al pedir acceso se comparte únicamente el archivo `.pub`, y los despliegues en AWS los ejecuta quien administra los ambientes con el equipo enterado.

## 7. Resumen de lecciones

1. **Contrastar las guías de IA con el proyecto real** (Docker vs. k3s) y reutilizar las convenciones existentes del equipo (`observability.sh`, `lib.sh`).
2. **Tratar infraestructura, reglas de alertas y dashboards como código:** generarlos, versionarlos y validarlos con pruebas offline (`promtool`, `ci/tests/`).
3. **Diseñar observabilidad entendiendo Kubernetes:** scrapear pods (no Services), revisar sondas de salud antes de probar alertas y verificar indentación y nombres exactos de variables de entorno.
4. **Dominar el entorno Windows + Git Bash:** usar `MSYS_NO_PATHCONV=1` en Docker, anteponer `/usr/bin` al `PATH` para `pytest`, asignar `+x` en Git y leer siempre la línea `Caused by:`.
5. **Cuidar la higiene de Git y Jira antes del PR:** confirmar la clave `PI-XX` y validar la convención de todos los commits de la rama.
6. **Validar en local con mocks y cerrar con datos reales:** desacoplar pruebas de AWS cuando el clúster es compartido y basar las retrospectivas en el historial real de commits y el burndown.
7. **La IA apoya el diagnóstico, pero la responsabilidad es mía:** validar cada cambio, respetar los acuerdos del equipo y declarar todas las herramientas usadas en `IAG_REGISTRO.md`.