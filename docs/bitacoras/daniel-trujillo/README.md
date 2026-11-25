# Bitácora de problemas y soluciones: Daniel Trujillo

**Proyecto:** CircleGuard, Parte 2 (Sprint 2, del 9 al 22 de noviembre de 2026)
**Rol:** Developer (infraestructura, Kubernetes y operación)
**Historias trabajadas:** TEC-09, HU-10, HU-11, HU-12, HU-23 (PI-36), HU-24 (PI-37) y HU-25 (PI-38), más la estabilización del despliegue en dev que hizo falta para que el pipeline llegara hasta el E2E

Esta bitácora recoge los problemas que me encontré en mi parte de la Parte 2 y cómo los resolví. La escribo para que, si a alguien del equipo le pasa algo parecido, vaya directo a la causa y no pierda el tiempo que perdí yo. Casi todo salió de desplegar en AWS de verdad: en el papel los manifiestos y los módulos de Terraform estaban bien, y los problemas aparecieron al ejecutarlos.

## Cómo usé la IA

Usé un asistente de IA (Claude) como apoyo cuando me trababa con un error: para leer logs largos de Jenkins y de Kubernetes, para pensar posibles causas de un fallo y para tener un primer borrador de algún script o de un párrafo de documentación. Después revisaba cada propuesta, la probaba y, si algo no cuadraba con lo que veía en el clúster, lo descartaba.

Lo que **no** le dejé a la IA:

- **Decidir qué se hacía.** El alcance de cada HU, qué se subía al repositorio y qué se dejaba como limitación lo decidimos en el equipo.
- **Tocar cosas compartidas sin avisar.** Abrir el firewall de Jenkins o entrar por SSH al nodo de dev lo hacía solo con mi autorización en ese momento y cerrando el acceso al terminar. Las contraseñas y los kubeconfigs nunca los puse en el chat ni en el repositorio.
- **Saltarse la revisión.** Todos los cambios entraron a `dev` por PR, con la aprobación de otra persona del equipo.

Este uso sigue el **Nivel 3: colaboración con IAG** que el equipo declaró en [`IAG_REGISTRO.md`](../../../IAG_REGISTRO.md).

---

## 1. TEC-09 y HU-10: módulos Terraform y ambientes con estado remoto (PR #45 al #53, #59, #61, #63, #66)

### Problema 1.1: `terraform plan` nunca llegaba a cero cambios

**Qué pasó.** Después de aplicar un ambiente, un `plan` inmediato volvía a proponer cambios: quería borrar la ruta del peering entre la VPC del ambiente y la de CI/CD.

**Por qué.** La tabla de rutas pública declara su ruta a Internet dentro del propio recurso, mientras que el peering se agrega aparte con un `aws_route`. Terraform interpretaba que la ruta del peering "sobraba" en cada ejecución.

**Cómo se resolvió.** Se ignoran los cambios de las rutas declaradas dentro de la tabla (`ignore_changes`), de modo que las dos formas de definir rutas convivan (PR #61).

**Lección.** Un `plan` que no queda limpio después de un `apply` casi siempre es un recurso que se está administrando de dos maneras a la vez. No conviene acostumbrarse a ignorar ese diff.

### Problema 1.2: una imagen nueva de Ubuntu podía reemplazar un nodo que estaba funcionando

**Qué pasó.** El módulo de cómputo toma la AMI de Ubuntu más reciente. Canonical publica imágenes nuevas con frecuencia, y en el siguiente `plan` Terraform proponía **reemplazar** instancias que ya corrían el clúster k3s.

**Cómo se resolvió.** Agregué `ignore_changes = [ami]` en el recurso de la instancia. Los nodos nuevos siguen tomando la imagen actual y, si hace falta una imagen fija, se usa la variable `ami_id` (PR #66).

**Lección.** Un nodo con estado no debe depender de un parámetro que cambia por fuera del repositorio.

### Problema 1.3: los nodos no podían bajar imágenes del Nexus privado

**Qué pasó.** Las imágenes de CircleGuard están en nuestro Nexus privado y los nodos k3s no tenían configurado ese registro ni sus credenciales, así que no podían descargarlas.

**Cómo se resolvió.** Los ambientes reciben variables para el registro y sus credenciales, y la plantilla de arranque del nodo las escribe en la configuración de registros de k3s. Los valores reales van en el `terraform.tfvars`, que no se sube (PR #59).

### Problema 1.4: el estado remoto y el huevo y la gallina

**Qué pasó.** El estado de Terraform vive en S3 con bloqueo, pero el bucket y la tabla de bloqueo también los tiene que crear alguien.

**Cómo se resolvió.** Una carpeta `bootstrap` crea esos recursos con estado local una sola vez y los ambientes (`dev`, `stage`, `prod`) usan después el backend remoto. Dejé documentado quién custodia el estado del bootstrap y cómo migrarlo (PR #51 y #52).

---

## 2. HU-11 y HU-12: Kubernetes, Ingress y autoescalado (PR #54, #55, #62)

### Problema 2.1: los servicios leían como configuración variables que Kubernetes inventaba

**Qué pasó.** Kafka, Neo4j y ZooKeeper arrancaban mal. Kubernetes inyecta variables `<NOMBRE>_PORT` por cada Service, y como varios Services se llaman igual que la aplicación, las imágenes las interpretaban como ajustes propios.

**Cómo se resolvió.** Se desactivaron los *service links* (`enableServiceLinks: false`) en esos pods.

### Problema 2.2: Neo4j leía todas sus variables `NEO4J_*` como ajustes

**Qué pasó.** La imagen toma cualquier variable que empiece por `NEO4J_` como una opción de configuración, así que el Secret con la contraseña rompía el arranque.

**Cómo se resolvió.** El Secret se expone como `GRAPH_DB_PASSWORD` y solo se exporta `NEO4J_AUTH`.

### Problema 2.3: tres servicios no tienen Actuator y sus sondas fallaban

**Qué pasó.** `dashboard`, `file` y `notification` no incluyen Actuator. Sus sondas apuntaban a `/actuator/health` y los pods nunca pasaban a `Ready`.

**Cómo se resolvió.** Esos tres usan una sonda TCP al puerto. Actualicé `validate.py` para que acepte esa excepción de forma explícita y no por casualidad.

### Problema 2.4: `file` escribe en una carpeta relativa y PostgreSQL se quedaba sin conexiones

**Qué pasó.**
- El servicio `file` guarda archivos en una carpeta `uploads` relativa, y el contenedor no tiene dónde escribir.
- Con 2 o más réplicas por servicio, PostgreSQL agotaba el límite por defecto de 100 conexiones.

**Cómo se resolvió.** `file` arranca desde un volumen con permiso de escritura, y PostgreSQL pasa a `max_connections` de 300 con 1536 Mi de memoria (PR #62).

**Lección.** Estos cuatro problemas solo aparecieron al desplegar en k3s real. Por eso quedaron como una sola corrección con la lista de hallazgos en el mensaje del commit.

---

## 3. HU-23: service mesh con mTLS y canary (PI-36, PR #73)

### Problema 3.1: el nodo de dev no tenía CPU para una malla

**Qué pasó.** El nodo de dev tiene 2 vCPU y los pods ya tenían reservada casi toda esa CPU. Una malla con un plano de control grande y un proxy por pod no cabía.

**Cómo se resolvió.** Elegí Linkerd, que es la opción más liviana, y le puse solicitudes mínimas: 5 m por componente del plano de control y 2 m por proxy, unos 21 m en total para el plano de control completo.

### Problema 3.2: la política estricta rompería a Traefik y a Prometheus

**Qué pasó.** Con la política `all-authenticated` solo se aceptan peticiones que vengan con mTLS. Traefik (la entrada) y Prometheus (las métricas) no están en la malla, así que quedarían rechazados.

**Cómo se resolvió.** La política estricta se demuestra en un namespace aparte, `mesh-demo`. En `circleguard-dev` los servicios sí están en la malla pero con la política permisiva por defecto. Extender la estricta a los servicios reales exige meter antes esos dos componentes en la malla, y lo dejé escrito como límite.

### Problema 3.3: las llaves de la malla no pueden ir al repositorio

**Cómo se resolvió.** El script `infra/mesh/issue-certs.sh` genera la raíz de confianza y el emisor de identidad (P-256, 30 días). Las llaves están en `.gitignore` y una prueba comprueba que siga siendo así.

**Lección.** Los certificados de la malla vencen a los 30 días. Es una malla de evaluación y no una de producción, y así quedó declarado.

---

## 4. HU-24: chaos engineering con Chaos Mesh (PI-37, PR #72)

### Problema 4.1: un experimento de caos no puede salirse de dev

**Qué pasó.** Chaos Mesh puede afectar a cualquier namespace. En un clúster con otros ambientes eso es un riesgo.

**Cómo se resolvió.** El controlador corre con `enableFilterNamespace` y solo actúa sobre namespaces con la anotación `chaos-mesh.org/inject=enabled`, que únicamente tiene `circleguard-dev`. Las pruebas de `ci/tests/test_chaos.py` exigen que cada experimento tenga hipótesis, apunte solo a dev y tenga duración si mantiene una falla.

### Problema 4.2: las imágenes que corrían en dev no exponían métricas

**Qué pasó.** Para probar que la alerta `ServiceDown` (HU-17) se dispara, Prometheus necesita `/actuator/prometheus`. Las imágenes que estaban corriendo en dev eran anteriores a esa HU y no lo exponían.

**Cómo se resolvió.** Construí la imagen de `identity` con el código de `dev` y la importé al nodo (`circleguard-identity-service:hu24-chaos`). Es una desviación temporal que dejé anotada en `registro-cambios-ambientes.md`, con su forma de deshacerla: el siguiente pipeline de dev la reemplaza.

**Resultado.** El experimento 1 mató un pod de `promotion` y el servicio siguió atendiendo por la otra réplica; el pod nuevo quedó listo unos 40 s después. En el experimento 2 la alerta `ServiceDown` pasó a *firing* 78 s después de aplicar la falla y se resolvió sola al terminar.

**Lección.** Escribir la hipótesis antes de ejecutar obliga a decidir qué se va a medir, y evita justificar el resultado después.

---

## 5. HU-25: FinOps (PI-38, PR #67 y #68)

### Problema 5.1: los créditos de AWS escondían el gasto

**Qué pasó.** Los créditos cubren todo, así que el gasto neto es cero y un presupuesto sobre ese valor nunca habría avisado de nada.

**Cómo se resolvió.** El presupuesto mide el gasto **bruto**. En el reporte de noviembre (1 al 20) el bruto fue de 27,45 USD, de los cuales el cómputo es el 56 %.

### Problema 5.2: el reporte por ambiente no tenía datos

**Qué pasó.** Cost Explorer no podía separar por ambiente porque las etiquetas no estaban activadas para costos.

**Cómo se resolvió.** Activé `Environment` y `Project` como etiquetas de asignación de costos. AWS no aplica la etiqueta hacia atrás, así que el desglose por ambiente empieza el 20 de noviembre y el gasto anterior aparece como "sin etiqueta". Lo dejé escrito en el informe.

### Problema 5.3: el HPA no ahorra nada

**Qué pasó.** El HPA de Kubernetes no baja de una réplica, y apagar pods no reduce la factura mientras las instancias EC2 sigan encendidas.

**Cómo se resolvió.** La escala a cero se hace en los nodos con EventBridge Scheduler: dev y stage se detienen a las 20:00 y se encienden a las 07:00 de lunes a viernes (hora de Bogotá). Un rol de IAM solo puede detener e iniciar los nodos de su ambiente y el módulo rechaza activarlo en prod. El ahorro estimado es de unos 128,80 USD frente a dejar todo encendido.

### Problema 5.4: el horario habría roto el pipeline de la entrega

**Qué pasó.** Un push a `dev` o a `main` despliega en dev y stage. Terraform no enciende instancias detenidas, así que con el horario activo esas etapas fallarían de noche.

**Cómo se resolvió.** Dejé `scale_to_zero_enabled = false` en dev y stage hasta después de la entrega del 22 de noviembre (PR #68). Pasada la entrega se activa en los dos.

**Lección.** Un ahorro que apaga el ambiente de pruebas hay que programarlo contra el calendario del proyecto.

### Problema 5.5: la IP pública cambia al encender un nodo

**Qué pasó.** Al encender un nodo cambia su IP pública y los kubeconfig locales apuntan a la anterior.

**Cómo se resolvió.** Jenkins usa las IP privadas por el peering y, en los kubeconfig locales, hay que actualizar la línea `server:`. Tras un encendido, k3s y los workloads vuelven solos, como se comprobó en la prueba de recuperación de la HU-10.

---

## 6. Estabilización del despliegue en dev (PR #81 al #92 y #94)

Esta fue la parte que más tiempo me llevó. Cuando el pipeline de `dev` llegó a las etapas de Kubernetes aparecieron problemas uno detrás de otro, y cada corrección dejaba ver el siguiente. Los agrupo por tipo.

### Seguridad de las imágenes (Trivy)

**Qué pasó.** El análisis de imágenes empezó a bloquear el pipeline por CVE en las dependencias.

**Qué hice.**
- Actualicé Spring Boot a 3.5.16 y Tomcat a 10.1.62 (#83), Netty a 4.1.141 (#86), Freemarker (#87) y los paquetes de Alpine de la imagen web (#88).
- Al subir de versión, Flyway 11 pidió el módulo `flyway-database-postgresql` (#84).
- Tres CVE de Spring que no aplican a nuestro uso quedaron en un archivo de excepciones con justificación y **fecha de vencimiento (23 de diciembre de 2026)**, para que no se queden olvidados. El plan de fondo es migrar a Spring Boot 4 (#85 y #87).

**Lección.** Una excepción de seguridad sin fecha de vencimiento se convierte en deuda permanente.

### El disco de Jenkins se llenaba

**Qué pasó.** Trivy descargaba sus bases de datos (cerca de 1 GB) dentro del *workspace* en cada build, y `cleanWs` las borraba. El disco se llenó y la etapa falló con `no space left on device`.

**Cómo se resolvió.** Las bases se guardan en un volumen de Docker con nombre, fuera del workspace, para descargarlas una sola vez (#81). Las reglas de escaneo no cambiaron.

### Scripts que fallaban por detalles de sistema

- **El wrapper de kubectl no era ejecutable.** Se había subido con modo `100644` desde Windows, así que en el checkout de Jenkins daba `Permission denied`. Lo corregí en Git (#89).
- **El aprovisionamiento de kubeconfig abortaba cuando todo estaba bien.** `kubectl auth can-i` devuelve código 1 cuando la respuesta es "no", y con `set -o pipefail` el script fallaba justo cuando el permiso estaba correctamente denegado. Ahora compara la respuesta impresa (#90).

### StatefulSets que no volvían tras reiniciar el nodo

**Qué pasó.** En la prueba de recuperación (apagar y encender el nodo de dev), Kafka y OpenLDAP no volvían.
- ZooKeeper solo persistía su carpeta de datos, no el log de transacciones; al reiniciar perdía el identificador del clúster y Kafka se negaba a unirse.
- OpenLDAP persistía la base pero no `/etc/ldap/slapd.d`, y la imagen no arranca en ese estado.

**Cómo se resolvió.** Cada uno conserva la carpeta que faltaba en su propio volumen. Kubernetes no permite modificar las plantillas de volumen de un StatefulSet que ya existe, así que este cambio no se puede aplicar encima de uno creado antes. Quedó verificado apagando y encendiendo el nodo: los 16 pods volvieron a estar listos sin intervención (#91).

### Rollouts que se quedaban en `Pending`

**Qué pasó.** El nodo de dev tiene 2 vCPU y sus pods reservan cerca del 98 %. Con la estrategia por defecto, cada actualización crea un pod extra por Deployment (el 25 % de `maxSurge` se redondea a uno), y esos pods quedaban `Pending` con `Insufficient cpu` hasta agotar el plazo del *rollout*.

**Dato importante.** La CPU **usada** era del 5 %; lo que se había agotado era la CPU **reservada**.

**Cómo se resolvió.** En dev se usa `maxSurge: 0` y `maxUnavailable: 1`, de modo que el pod nuevo ocupa el lugar del anterior. Stage y prod mantienen el valor por defecto (#92).

**Lección.** Hay que mirar las solicitudes (`requests`) y no solo el consumo real cuando un pod no se programa.

### El E2E fallaba antes de empezar

**Qué pasó.** El E2E de dev se detenía con HTTP 401 al hacer login con la cuenta dedicada del gate.

**Cómo lo investigué.**
- El LDAP de dev está vacío (ni siquiera existe `ou=people`), así que todo login se resuelve contra la tabla `local_users` de la base `circleguard_auth`.
- Esa tabla solo traía los tres usuarios de la semilla de Flyway. Las cuentas `e2e_gate` y `e2e_survey`, que estaban en las credenciales de Jenkins, no existían en dev.

**Cómo se resolvió.** El paso de E2E ahora asegura las dos cuentas antes de ejecutar las pruebas, solo en dev (PR #94):
- la contraseña viaja por la entrada estándar de `kubectl exec` y nunca aparece en argumentos ni en el log;
- el hash lo calcula PostgreSQL con `pgcrypto`, compatible con el `BCryptPasswordEncoder` de Spring;
- el script rechaza por nombre a `staff_guard`, `health_user` y `super_admin`, para no tocar nunca a los usuarios de la semilla;
- si la contraseña de Jenkins cambia, se actualiza; si no, no modifica nada.

**Cómo lo comprobé.** Antes de integrarlo lo probé contra el dev real con dos cuentas temporales y contraseñas descartables, que borré al terminar: el login devolvió 200 con el permiso `gate:scan` para el gate, 401 con una contraseña incorrecta, una segunda ejecución no cambió ninguna fila y los hashes de los usuarios de la semilla quedaron intactos. A raíz de la revisión del PR, la extensión `pgcrypto` ya no la crea el E2E sino la inicialización de la base de datos.

**Lección.** Las pruebas con *mocks* no demuestran que el aprovisionamiento funcione. Hay que probarlo contra la base real, aunque sea con datos temporales.

---

## 7. Prácticas que repetí en todos los cambios

- **Credenciales fuera del repositorio.** Las llaves SSH, los `terraform.tfvars`, los kubeconfigs y las contraseñas de las cuentas de prueba viven en Jenkins o en archivos locales fuera de Git. Nunca los pasé como argumentos de comandos ni los imprimí en un log.
- **Accesos temporales.** Cuando tuve que abrir el firewall de Jenkins o el SSH del nodo de dev, lo hice para mi IP del momento y lo cerré al terminar.
- **Cambios en ambientes compartidos con rastro.** Cada cambio manual en dev (por ejemplo la imagen local de `identity` o la extensión `pgcrypto`) quedó anotado, con la forma de deshacerlo, en `docs/operaciones/registro-cambios-ambientes.md` o en el PR.
- **Una corrección por problema.** Prefiero un PR pequeño por cada causa que uno grande con varias, porque así el revisor puede aprobarlo y, si algo sale mal, se revierte solo ese cambio.

## 8. Resumen de lecciones

1. **Los problemas reales aparecen al desplegar.** Casi todo lo de las secciones 2 y 6 pasó con k3s y AWS de verdad, no con `validate.py` ni con las pruebas locales.
2. **Reservado no es lo mismo que usado.** Un nodo con 5 % de CPU en uso puede estar lleno para Kubernetes.
3. **Un `plan` limpio después de un `apply` es una señal de salud.** Si no queda en cero, hay un recurso administrado de dos maneras.
4. **Todo lo que ahorra o protege necesita fecha.** El horario de apagado, las excepciones de Trivy y los certificados de la malla tienen vencimientos que dejé escritos.
5. **Comprobar contra el ambiente real antes de integrar.** Una prueba con datos temporales que se borran al terminar da mucha más confianza que un *mock*.
6. **La IA ayuda a leer un log y a proponer causas, pero la decisión, la prueba y la responsabilidad son del equipo:** qué se cambia, qué se sube y a quién se le pide permiso.
