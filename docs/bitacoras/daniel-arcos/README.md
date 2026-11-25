# Bitácora de problemas y soluciones: Daniel Esteban Arcos Cerón [A00400760]

**Proyecto:** CircleGuard, pipeline DevOps de extremo a extremo  
**Asignatura:** Ingeniería de Software V, Grupo 005, Universidad Icesi, 2026-2  
**Periodo:** Sprints 0, 1 y 2 (28 de octubre al 22 de noviembre de 2026)  
**Rol:** Product Owner y desarrollador  
**Historias de usuario y tareas técnicas trabajadas:** TEC-02, HU-01, HU-02, TEC-07, TEC-08, HU-13, HU-20, TEC-11 y TEC-13, además del apoyo en la estabilización del despliegue de DEV (HU-11).

Esta bitácora documenta de manera individual y transparente el uso de inteligencia artificial generativa durante el desarrollo de CircleGuard, conforme a la política de colaboración de Nivel 3 del proyecto. Registra en qué actividades usé la IA, qué problema motivó la consulta, qué respuesta obtuve, qué decisiones tomé a partir de ella y qué aprendí.

Su propósito es que, si otro integrante del equipo se encuentra con una situación similar, pueda identificar la causa y aplicar una solución sin repetir todo el proceso de diagnóstico. También se incluyen los prompts utilizados para documentar el aporte de la inteligencia artificial en cada caso.

## Cómo usé la IA

Usé un asistente de IA (ChatGPT) como apoyo cuando encontraba un error o tenía dudas sobre una implementación. Lo utilicé principalmente para interpretar logs de Jenkins, analizar el almacenamiento de Docker, plantear comandos de diagnóstico en Kubernetes, comprobar la idempotencia de scripts Bash y contrastar alternativas de dimensionamiento de instancias EC2.

Las respuestas sirvieron como punto de partida para investigar los problemas. Revisé las propuestas, adapté los comandos al contexto del proyecto y comprobé los resultados antes de tomar una decisión.

Lo que **no** le dejé a la IA:

- **Decidir qué se hacía en el proyecto.** El alcance de las historias, las decisiones de implementación, el dimensionamiento de las instancias y los cambios que se subían al repositorio los decidí con el equipo.
- **Tocar ambientes compartidos sin revisión.** Antes de ejecutar comandos de limpieza, reinicio o modificación en Jenkins, AWS o Kubernetes, verifiqué su alcance y su posible impacto sobre los servicios, volúmenes persistentes y demás ambientes.
- **Dar por bueno un resultado sin comprobarlo.** Las propuestas se validaron mediante logs, estados de contenedores, pruebas y resultados observables.
- **Gestionar credenciales.** Ninguna contraseña, llave privada o credencial fue compartida con la IA.

Este uso sigue el **Nivel 3: colaboración con IAG** que el equipo declaró en [`IAG_REGISTRO.md`](../../../IAG_REGISTRO.md).

---

## 1. HU-01: Bootstrap de la plataforma CI/CD

**Qué pide la historia.** Como ingeniero de plataforma, quiero scripts Bash idempotentes que instalen Jenkins, SonarQube y Nexus, para reconstruir la plataforma de CI/CD desde cero con un solo comando.

**Criterios de aceptación del backlog:**

- Existen los scripts infra/bootstrap-*.sh basados en Docker Compose.
- Ejecutar un script dos veces no rompe ni duplica la configuración.
- Jenkins, SonarQube y Nexus quedan accesibles por URL y el docente puede ingresar a Jenkins.
- Ninguna credencial queda en el repositorio.

### Problema 1.1: comprobar que los scripts de bootstrap son idempotentes

**Qué pasó.** La infraestructura inicial necesitaba tres servicios de CI/CD disponibles en EC2: Jenkins, SonarQube y Nexus. Tenía dudas sobre cómo comprobar que los scripts de bootstrap pudieran ejecutarse varias veces sin recrear usuarios, volúmenes ni credenciales.

**Por qué.** Una instalación manual dificulta la recuperación del entorno cuando se apagan o recrean instancias. Además, que un script termine correctamente al ejecutarlo por segunda vez no garantiza que haya conservado el estado de los servicios.

**Prompt.**

> ¿Cómo comprobar que un script Bash de bootstrap es idempotente y no recrea usuarios, volúmenes ni credenciales al ejecutarlo varias veces?

**Cómo se resolvió.** La IA propuso comparar el estado de la infraestructura antes y después de una segunda ejecución del bootstrap. Los comandos y verificaciones que utilicé o adapté fueron:

- **Sintaxis y robustez del script:** `bash -n infra/bootstrap-cicd.sh` y `shellcheck`, además de verificar el uso de `set -euo pipefail`.
- **Estado de los contenedores:** `sudo docker ps --format '{{.Names}} {{.ID}} {{.Status}}'` antes y después de la ejecución. Los IDs y el tiempo de actividad debían conservarse, sin contenedores duplicados.
- **Volúmenes persistentes:** `sudo docker volume ls` y `sudo docker volume inspect <volumen>`. Los seis volúmenes debían conservar su identidad y fecha de creación.
- **Credenciales sin exponerlas:** `sudo sha256sum /opt/circleguard/jenkins/jenkins.secrets.env`, junto con los archivos equivalentes de SonarQube y Nexus. Los hashes debían coincidir entre ejecuciones.
- **Validación de Docker Compose:** `docker compose -f compose.yaml config --quiet` y comprobación de que `up -d` no recreara innecesariamente los servicios.
- **Verificación final de solo lectura:** `bash infra/bootstrap-verify.sh; echo "EXIT_CODE=$?"`.

Ejecuté el bootstrap unificado dos veces consecutivas y comparé las salidas. La idempotencia no se dio por válida únicamente mediante la inspección del código, sino mediante la comprobación de los hashes, los IDs de los contenedores y los volúmenes persistentes.

**Lección.** Idempotente no significa simplemente que un script no falle al repetirlo, sino que deje el sistema en el mismo estado. Las credenciales generadas deben crearse únicamente cuando no existan (`if ! test -f secrets.env`) y pueden compararse mediante hashes sin exponer su contenido. Asimismo, los scripts de verificación deben ser de solo lectura para que puedan ejecutarse repetidamente sin alterar la infraestructura.

### Resultado de la comprobación de idempotencia (HU-01)

Se comprobó la disponibilidad de Jenkins, SonarQube y Nexus, así como la conservación del estado de la infraestructura entre ejecuciones del bootstrap:

- Código de salida `EXIT_CODE=0`.
- Cuatro contenedores sin duplicados.
- Seis volúmenes persistentes intactos.
- Credenciales conservadas entre ejecuciones.

Las evidencias se encuentran en `infra/bootstrap-cicd.sh`, los scripts relacionados, las verificaciones de los servicios y las Figuras 9 y 10 del informe de la Parte 1.

---

## 2. HU-02: Ambientes con Docker Compose

**Qué pide la historia.** Como ingeniero de plataforma, quiero un docker-compose por ambiente con healthchecks y la configuración fuera del repositorio, para ejecutar los servicios núcleo de forma aislada y reproducible en dev, stage y prod.

**Criterios de aceptación del backlog:**

- Cada ambiente ejecuta auth, identity, promotion, form, gateway, el cliente web y su middleware.
- Cada servicio tiene healthcheck sobre /actuator/health.
- Las URL y credenciales se leen de variables de entorno, sin valores en texto plano en el repositorio.
- La misma imagen funciona en los tres ambientes sin reconstruirse.

### Problema 2.1: memoria insuficiente en las instancias de ambiente

**Qué pasó.** Inicialmente se seleccionaron instancias `t3.small` de 2 GiB de RAM para los ambientes dev, stage y prod. Sin embargo, al desplegar los 12 contenedores de cada ambiente, los servicios no conseguían arrancar de forma estable.

Cada ambiente ejecutaba:

- Cinco microservicios núcleo desarrollados con Spring Boot.
- Un cliente web servido mediante nginx.
- Seis servicios de middleware: PostgreSQL, Neo4j, ZooKeeper, Kafka, Redis y OpenLDAP.

**Por qué.** La memoria disponible era insuficiente para ejecutar simultáneamente las JVM de los microservicios, Neo4j, Kafka y los demás componentes de la infraestructura. El dimensionamiento inicial no contemplaba adecuadamente el consumo acumulado de todos los procesos.

**Prompt.**

> El tamaño escogido para las instancias (`t3.small`, 2 GiB) es adecuado para correr 5 microservicios Spring Boot, un cliente web nginx, PostgreSQL, Neo4j, Kafka, ZooKeeper, Redis y OpenLDAP en la misma EC2 con Docker Compose?

> Los contenedores no arrancan de forma estable. ¿Qué tamaño de instancia me recomiendas dentro de las opciones disponibles para el plan gratuito de AWS?

**Cómo se resolvió.** La IA propuso utilizar instancias de propósito general de la familia *flex*, específicamente `m7i-flex.large` (2 vCPU y 8 GiB de RAM), argumentando que ofrecían mayor capacidad de memoria y que eran elegibles dentro de las opciones del plan gratuito de AWS consideradas en ese momento.

Adopté esta configuración para los tres ambientes y mantuve los servidores de CI/CD en instancias `c7i-flex.large` de 4 GiB de RAM.

Adicionalmente, se incorporó una validación en `deploy-env.sh` que impide realizar el despliegue en una máquina con menos de aproximadamente 7 GiB de RAM. De esta manera, una configuración insuficiente se detecta antes de iniciar los contenedores.

El cambio y su impacto económico quedaron documentados en `infra/docs/costs.md`, conservando la estimación inicial para mantener la trazabilidad de la decisión.

**Lección.** La capacidad de una instancia debe determinarse a partir de los recursos que requieren los procesos que ejecutará y no únicamente por intuición. También hay que considerar el impacto económico: el costo estimado por hora pasó de 0,3468 a 0,5718 USD con todas las instancias encendidas. Por eso, el dimensionamiento debe acompañarse de prácticas de control de costos, como apagar las instancias cuando no se utilizan.

### Resultado del ajuste de capacidad (HU-02)

Se amplió la capacidad de memoria de los ambientes para soportar los contenedores del laboratorio:

| Componente | Configuración inicial | Configuración adoptada |
| --- | --- | --- |
| Dev | `t3.small` (2 GiB) | `m7i-flex.large` (8 GiB) |
| Stage | `t3.small` (2 GiB) | `m7i-flex.large` (8 GiB) |
| Prod | `t3.small` (2 GiB) | `m7i-flex.large` (8 GiB) |
| CI/CD | `c7i-flex.large` (4 GiB) | Sin cambios |

La modificación quedó documentada en el informe de la Parte 1, en `infra/docs/costs.md` y en la validación de memoria incorporada en `deploy-env.sh`.

---

## 3. HU-13: Despliegue a Kubernetes desde el pipeline

**Qué pide la historia.** Como responsable de release, quiero que Jenkins aplique Terraform, escanee con Trivy y despliegue a Kubernetes con promoción entre ambientes, para gobernar la infraestructura y la aplicación desde el pipeline.

**Criterios de aceptación del backlog:**

- El pipeline ejecuta terraform plan y apply, con aprobación en prod.
- Trivy escanea imágenes e IaC y detiene el pipeline ante vulnerabilidades CRITICAL.
- El pipeline despliega a Kubernetes y promueve de dev a stage y a prod con aprobación.
- Los fallos se notifican.

### Problema 3.1: falta de almacenamiento en Jenkins durante el escaneo de Trivy (builds #51 y #52)

**Qué pasó.** El build #51 de Jenkins superó las etapas de compilación, pruebas, cinco Quality Gates y empaquetamiento, pero falló al intentar inicializar la base de datos Java de Trivy con el siguiente error:

```
no space left on device
```

Después de realizar una primera limpieza del servidor, el build #52 presentó nuevamente el mismo problema.

**Por qué.** Jenkins y su agente de compilación compartían el mismo disco raíz de la instancia EC2. La acumulación de imágenes Docker, caché de compilación y las bases de datos de vulnerabilidades de Trivy reducía progresivamente el almacenamiento disponible.

Además, las bases de datos de Trivy, de aproximadamente 1 GB, se descargaban dentro del workspace y podían eliminarse durante su limpieza, lo que obligaba a descargarlas nuevamente en ejecuciones posteriores.

**Prompt.**

> ¿Qué recursos Docker puedo limpiar sin eliminar volúmenes persistentes ni contenedores utilizados por Jenkins?

**Cómo se resolvió.** La IA me ayudó a interpretar las salidas de `df` y `docker system df`, identificar los montajes del agente de compilación y distinguir entre los recursos Docker que podían eliminarse y aquellos que conservaban información persistente.

Primero verifiqué el almacenamiento disponible:

```bash
df -h /
sudo docker system df
```

Después ejecuté una limpieza de caché de compilación e imágenes no utilizadas:

```bash
sudo docker builder prune -f
sudo docker image prune -f
```

Con esta primera intervención, el espacio disponible pasó de aproximadamente 3,7 GB a 5,8 GB.

Posteriormente, tras comprobar que no había builds activos, ejecuté una limpieza más amplia de imágenes sin uso:

```bash
sudo docker image prune -a -f
```

Esta operación recuperó 6,117 GB adicionales.

Finalmente, verifiqué nuevamente el almacenamiento y el estado de los contenedores de Jenkins y del agente de compilación.

No eliminé volúmenes persistentes ni contenedores.

Como solución de fondo, el equipo configuró las bases de datos de Trivy para almacenarse en un volumen Docker con nombre, fuera del workspace, evitando descargarlas nuevamente en cada build.

**Lección.** Antes de limpiar un servidor de CI/CD, hay que distinguir entre los recursos temporales y aquellos que conservan el estado de la infraestructura. La caché de compilación y las imágenes sin uso pueden eliminarse después de revisar su impacto, pero los volúmenes persistentes deben conservarse.

Una limpieza más agresiva con `docker image prune -a` debe realizarse únicamente después de comprobar que no hay builds activos ni imágenes necesarias para ejecuciones pendientes. El comando `docker volume prune` no debe utilizarse como una alternativa de limpieza rápida.

### Resultado de la recuperación de almacenamiento

| Indicador | Resultado |
| --- | --- |
| Espacio disponible inicialmente | 3,7 GB aproximadamente |
| Espacio después de la primera limpieza | 5,8 GB aproximadamente |
| Espacio adicional recuperado | 6,117 GB |
| Espacio disponible al finalizar | 12 GB aproximadamente |
| Uso final del disco | 59 % |
| Estado de `circleguard-jenkins` | Healthy |
| Estado de `circleguard-build-agent` | Activo |
| Volúmenes y contenedores eliminados | Ninguno |

Las evidencias se encuentran en los logs de los builds #51 y #52, las salidas de `df -h` y `docker system df` antes y después de la limpieza, y la fila «Poco espacio en Jenkins» de la sección 11.1 del README principal.

---

## 4. HU-11: Despliegue de CircleGuard en Kubernetes (apoyo en DEV)

**Qué pide la historia.** Como ingeniero de plataforma, quiero desplegar los 8 servicios, el cliente web y el middleware en Kubernetes, para operar CircleGuard completo sobre un clúster.

**Criterios de aceptación del backlog:**

- Hay un namespace por ambiente.
- Los 8 servicios, el cliente web y el middleware quedan en estado Running.
- La configuración está en ConfigMaps y las credenciales en Secrets.

Esta historia no me fue asignada directamente. Participé como apoyo en el diagnóstico y recuperación del ambiente DEV debido a que los problemas de disponibilidad impedían que el pipeline completara el despliegue.

### Problema 4.1: fallos de autenticación y disponibilidad durante el despliegue en DEV

**Qué pasó.** El pipeline superó las etapas previas de compilación, pruebas y controles de seguridad, pero falló en Deploy Dev porque Kubernetes no consiguió completar el rollout del Deployment `auth`.

El build #65 de Jenkins registró el siguiente error:

```
Waiting for deployment "auth" rollout to finish:
0 of 1 updated replicas are available...
error: deployment "auth" exceeded its progress deadline
```

**Prompt.**

> El pipeline volvió a fallar, y ahora marca la etapa Deploy Dev como fallida, ayúdame a realizar las validaciones necesarias para determinar la causa raíz del problema.

**Cómo se investigó.** La IA propuso una serie de comandos en Bash para revisar el ambiente y determinar la causa del fallo. A partir de ellos, realicé las siguientes comprobaciones:

1. **Estado de los pods.** Los servicios `auth`, `identity`, `form`, `promotion` y `dashboard` se encontraban en `CrashLoopBackOff`, con 1/2 contenedores listos. Otros componentes, como Kafka, Neo4j, Redis, OpenLDAP, Prometheus y Jaeger, estaban en ejecución.

2. **Logs de los servicios afectados.** Spring Boot terminaba con código de salida 1 al inicializar Flyway debido a un error de autenticación contra PostgreSQL:

   ```
   password authentication failed for user "cg_app"
   SQL State: 28P01
   ```

   El mismo error aparecía en `identity` y `form`. Los logs de PostgreSQL también mostraban los intentos de autenticación rechazados.

3. **Configuración del Secret.** Se comprobó que PostgreSQL y los servicios consumían `DB_USER` y `DB_PASSWORD` desde el mismo Secret, `circleguard-secrets`, por lo que inicialmente se esperaba que las credenciales coincidieran.

4. **Prueba aislada de PostgreSQL.** Se verificó que era posible conectarse desde el propio contenedor de PostgreSQL utilizando su contraseña. Esto permitió descartar una indisponibilidad general del motor y concentrar el diagnóstico en las diferencias entre las credenciales utilizadas por los servicios y el estado persistente.

**Por qué.** Las comprobaciones permitieron orientar el diagnóstico hacia inconsistencias entre las credenciales utilizadas por los servicios y las almacenadas en los componentes de middleware con estado persistente.

En particular, modificar un Secret de Kubernetes no implica que las credenciales previamente inicializadas en una base de datos con almacenamiento persistente se actualicen automáticamente.

También se identificó un problema adicional en `auth`: el indicador de salud LDAP de Spring Boot Actuator impedía que el servicio superara la comprobación de disponibilidad.

**Cómo se resolvió.** Durante la recuperación del ambiente identificamos y corregimos problemas de autenticación relacionados con PostgreSQL, Redis, Neo4j y OpenLDAP.

En el caso de `auth`, se aplicó temporalmente la siguiente variable de entorno:

```yaml
MANAGEMENT_HEALTH_LDAP_ENABLED: "false"
```

Esto permitió que el servicio superara la comprobación de salud y completara su rollout.

Sin embargo, desactivar el indicador de salud LDAP no demuestra que la autenticación mediante LDAP funcione correctamente. Por ello, el ajuste se trató como una mitigación temporal y quedó documentado en el overlay de DEV.

Adicionalmente, `secrets.sh` quedó configurado para bloquear el despliegue cuando detecta diferencias en los secretos existentes, en lugar de sobrescribirlos automáticamente y provocar inconsistencias con el estado persistente.

**Lección.** El diagnóstico debe comenzar con evidencia: estado de los pods, logs, configuración y pruebas aisladas. No conviene modificar servicios o configuraciones antes de identificar qué está fallando.

Un servicio marcado como disponible por Kubernetes no necesariamente funciona correctamente desde el punto de vista funcional. Desactivar un indicador de salud permite recuperar temporalmente la disponibilidad, pero no reemplaza la validación de la funcionalidad afectada.

Asimismo, los secretos previamente aplicados a componentes con almacenamiento persistente requieren un procedimiento de rotación; no basta con modificar el Secret de Kubernetes.

### Resultado del apoyo en la HU-11

Después de aplicar las correcciones y la mitigación temporal, se verificó la disponibilidad de los 12 Deployments de DEV.

Las evidencias de la recuperación fueron:

- Logs del build #65 de Jenkins.
- Estado de los pods durante el diagnóstico.
- Logs de `auth`, `identity`, `form` y PostgreSQL.
- Pruebas aisladas de conectividad y autenticación.
- Mitigación temporal documentada en el overlay de DEV mediante `MANAGEMENT_HEALTH_LDAP_ENABLED`.
- Verificación de disponibilidad de los 12 Deployments después de la recuperación.

**Limitaciones.** La recuperación confirmó la disponibilidad operativa del ambiente DEV, pero no la validación funcional completa de la autenticación LDAP.

Asimismo, el resultado corresponde a la recuperación realizada directamente en el ambiente. Al momento de documentar este caso, la ejecución automática completa de Jenkins después de integrar el PR en `dev` permanecía pendiente de validación.

---

## 5. Buenas prácticas de seguridad

- **Credenciales fuera del repositorio y de la IA.** Las contraseñas, llaves privadas y demás secretos no deben compartirse con asistentes de IA ni incorporarse al repositorio. Para verificar que un archivo de credenciales no cambió, se pueden comparar sus hashes sin mostrar su contenido.

- **Conservación de volúmenes persistentes.** Las operaciones de limpieza de Docker deben limitarse a los recursos que puedan eliminarse sin comprometer el estado de la infraestructura. No se debe utilizar `docker volume prune` como mecanismo de limpieza rápida en Jenkins.

- **Verificación previa a la ejecución del pipeline.** Antes de iniciar un nuevo build, conviene revisar el espacio disponible en el servidor Jenkins y su agente, realizar una limpieza segura de caché e imágenes sin uso cuando sea necesario y comprobar nuevamente el almacenamiento.

- **Cambios controlados en ambientes compartidos.** Antes de ejecutar comandos que modifiquen Jenkins, AWS o Kubernetes, se debe revisar su alcance y su impacto sobre los servicios, los datos persistentes y los demás integrantes del equipo.

- **Protección de los secretos existentes.** Los cambios de credenciales en servicios con almacenamiento persistente deben realizarse mediante procedimientos controlados. Sobrescribir un Secret no garantiza que la contraseña almacenada por una base de datos se actualice.

- **Documentación de mitigaciones temporales.** Los ajustes que recuperan la disponibilidad de un servicio, pero no solucionan completamente su problema funcional, deben quedar documentados junto con sus limitaciones.

---

## 6. Resumen de lecciones

1. **La idempotencia se demuestra comparando estados.** Un script que se ejecuta correctamente varias veces no es necesariamente idempotente. Se deben comprobar los contenedores, volúmenes y credenciales antes y después de su ejecución.

2. **Dimensionar la infraestructura a partir de las necesidades reales.** La capacidad de una instancia debe considerar los requerimientos acumulados de los servicios que ejecuta y el impacto económico de la configuración seleccionada.

3. **Prevenir los problemas de almacenamiento en CI/CD.** Revisar periódicamente el espacio disponible, distinguir entre recursos temporales y persistentes, y evitar descargas innecesarias permite reducir los fallos del pipeline.

4. **Diagnosticar antes de modificar.** Los logs, estados de contenedores y pruebas aisladas permiten descartar hipótesis y orientar las intervenciones hacia la causa del problema.

5. **La disponibilidad no equivale a la funcionalidad.** Que Kubernetes reporte un Deployment como disponible no garantiza que todos los flujos de negocio funcionen correctamente.

6. **Diferenciar una mitigación temporal de una solución definitiva.** Recuperar un ambiente no significa haber resuelto todos sus problemas. Las limitaciones y validaciones pendientes deben quedar explícitas.

7. **Mantener la trazabilidad de las decisiones.** Los cambios de infraestructura, capacidad, costos y configuración deben documentarse junto con las evidencias que justifican su implementación.

8. **La IA es una herramienta de colaboración, no de decisión.** Su aporte consiste en facilitar el diagnóstico, proponer alternativas y ayudar a comprender errores. La revisión, ejecución, validación y responsabilidad sobre los cambios siguen siendo mías y del equipo.
