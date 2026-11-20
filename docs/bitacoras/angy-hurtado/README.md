# Bitácora de problemas y soluciones: Angy Hurtado

**Proyecto:** CircleGuard, Parte 2 (Sprint 2, del 9 al 22 de noviembre de 2026)
**Rol:** Scrum Master y desarrolladora
**Historias trabajadas:** HU-16 (PI-25), HU-15 (PI-24), TEC-10 (PI-32), HU-21 (PI-30) y la revisión del PR #50

Esta bitácora es una guía de los problemas que me encontré en esta fase y de cómo los resolví. La escribo para que, si a alguien del equipo le pasa lo mismo, pueda ir directo a la solución sin perder el tiempo que perdí yo.

## Cómo usé la IA

Usé un asistente de IA (Claude) como apoyo cuando me trababa con un error o un conflicto concreto: un test que fallaba, un comando que no funcionaba en Windows o una configuración de AWS que no me dejaba entrar. Lo usé para entender por qué pasaba cada error y qué alternativas tenía, de forma parecida a como uno le pregunta a un monitor o a un compañero que sabe más del tema.

Lo que **no** le dejé a la IA:

- **Decidir qué se hacía en el proyecto.** El alcance de cada HU, los objetivos de rendimiento y qué se subía al repositorio los decidí yo con el equipo.
- **Tocar cosas compartidas sin permiso.** Antes de escribir en la base de datos de stage o cambiar el firewall lo consultaba con mis compañeros. La herramienta incluso tiene un bloqueo que no la deja escribir sola en sistemas compartidos.

Este uso sigue el **Nivel 3: colaboración con IAG** que el equipo declaró en [`IAG_REGISTRO.md`](../../../IAG_REGISTRO.md).

---

## 1. HU-16: caché del dashboard (PI-25, PR #57)

### Problema 1.1: un test pasaba solo y fallaba con los demás

**Qué pasó.** Las pruebas de la caché adelantan un reloj falso para simular que venció el TTL. Cada prueba sola pasaba, pero al correr todas juntas fallaban.

**Por qué.** Spring reutiliza el mismo contexto entre clases de prueba, así que el reloj falso también era compartido. Una prueba dejaba el reloj adelantado y la siguiente arrancaba con la caché ya vencida.

**Cómo se resolvió.** En el `setUp` de cada prueba se vuelve a poner el reloj en la hora inicial (`clock.set(START)`).

**Lección.** Si un bean de prueba guarda estado, hay que reiniciarlo antes de cada test. Si no, el orden de ejecución cambia el resultado.

### Problema 1.2: una línea del README desapareció en un merge

**Qué pasó.** El revisor aprobó el PR, pero comentó que faltaba el enlace al documento del patrón en el README de `docs/patrones`.

**Por qué.** Al resolver un conflicto con la rama `dev`, se quedó la versión del otro lado y se perdió mi línea.

**Cómo se resolvió.** Restauré la línea en un commit nuevo dentro del mismo PR, para no tener que abrir otro.

**Lección.** Después de resolver un conflicto, hay que revisar el diff completo y no solo confiar en que compila.

---

## 2. HU-15: configuración externa y feature toggle (PI-24, PR #58)

### Problema 2.1: el revisor encontró un `NullPointerException`

**Qué pasó.** Un compañero vio en la revisión que `Set.of(...).contains(null)` lanza `NullPointerException`. Un usuario sin ningún evento de salud no tiene clave en Redis, así que su estado es `null` y la validación en portería se caía.

**Cómo se resolvió.** Agregué la comprobación `if (status == null)` antes de mirar los conjuntos de estados. Un usuario sin clave entra con `GREEN`, con el toggle encendido o apagado. También agregué pruebas para ese caso, en la prueba unitaria y en la de Spring Boot completa.

**Lección.** Las colecciones inmutables de Java (`Set.of`, `List.of`) no aceptan `null`, ni siquiera para preguntar si lo contienen.

### Problema 2.2: un comando de verificación me borró el arreglo

**Qué pasó.** Para comprobar que la prueba nueva sí detectaba el error, quité el arreglo a propósito y luego lo restauré con `git checkout -- archivo`. Ese comando devolvió el archivo al último commit y borró también el arreglo, que todavía no había guardado en un commit.

**Cómo se resolvió.** Volví a aplicar el cambio a mano.

**Lección.** `git checkout -- archivo` descarta todo lo que no está en un commit. Antes de un experimento así conviene hacer `git stash` o un commit temporal.

### Problema 2.3: kustomize no acepta rutas absolutas

**Qué pasó.** Para probar que cambiar el toggle en el ConfigMap no cambia ningún Deployment, el script `validate.py` arma un overlay temporal. Al apuntarlo a la carpeta temporal del sistema, kustomize lo rechazaba.

**Cómo se resolvió.** La carpeta temporal se crea dentro de `infra/k8s` y el overlay usa la ruta relativa `../overlays/dev`.

---

## 3. TEC-10: documento de patrones de diseño en Word (PI-32, PR #60)

### Problema 3.1: no tenía cómo revisar el Word visualmente

**Qué pasó.** El documento se genera con un script y quería ver cómo quedaba cada página. En mi equipo no hay LibreOffice ni `pdftoppm`, que son los programas que se usan normalmente para convertir el documento a imágenes.

**Cómo se resolvió.** Exporté el documento a PDF con el mismo Microsoft Word, controlándolo desde un script, y convertí el PDF a imágenes con la librería PyMuPDF.

### Problema 3.2: pip no podía descargar librerías

**Qué pasó.** `pip install` fallaba con un error de certificado SSL.

**Por qué.** El antivirus Avast revisa las conexiones HTTPS y pone su propio certificado en el medio, y Python no confía en ese certificado.

**Cómo se resolvió.** Indiqué el certificado de Avast con `--cert "C:\ProgramData\Avast Software\Avast\wscert.pem"`. Este mismo problema volvió a salir con la CLI de AWS (ver 4.3).

### Problema 3.3: errores de formato en el documento

**Qué pasó.** Aparecía una página en blanco después de la Tabla 1, y los párrafos justificados con nombres de clases largos quedaban con espacios enormes entre palabras.

**Cómo se resolvió.**
- Quité el espacio que sobraba después de la tabla.
- Los párrafos que tienen código quedaron alineados a la izquierda.
- Ajusté el ancho de las columnas de la Tabla 1.

Para no partir de cero, reutilicé la plantilla del informe de la Parte 1, con el mismo encabezado, estilos y portada.

---

## 4. HU-21: pruebas de rendimiento y seguridad en stage (PI-30, PR #64)

Esta fue la HU con más problemas, porque necesitaba el ambiente real de stage en AWS y casi todo estaba apagado o sin configurar en mi equipo.

### Problema 4.1: el agente de Jenkins no tiene Python

**Qué pasó.** Mi primer script leía la configuración de la carga con `python3`. Al revisar el Dockerfile del agente de Jenkins vi que solo trae `git`, `curl`, `jq` y `netcat`.

**Cómo se resolvió.** La configuración se lee con `jq`. El evaluador de objetivos (`evaluate.py`) corre dentro de la imagen de Locust, que sí trae Python.

### Problema 4.2: las pruebas fallaban por la consola de Windows

**Qué pasó.** El evaluador imprime símbolos como `≤`. En Windows la consola usa la codificación `cp1252`, que no los tiene, y el programa se caía con `UnicodeEncodeError`.

**Cómo se resolvió.** El script fuerza UTF-8 al imprimir (`sys.stdout.reconfigure(encoding="utf-8")`).

### Problema 4.3: Docker apagado y AWS sin credenciales

**Qué pasó.**
- Docker Desktop no estaba abierto.
- La CLI de AWS no tenía ningún perfil configurado en mi usuario de Windows.
- Cuando ya tuve las credenciales del equipo, la CLI fallaba con `CERTIFICATE_VERIFY_FAILED`.

**Cómo se resolvió.**
- Abrí Docker Desktop.
- Configuré el perfil `circleguard` con las credenciales que me dio un compañero.
- Al perfil le agregué `ca_bundle` apuntando al certificado de Avast, que es el mismo problema del punto 3.2.

### Problema 4.4: no podía llegar al clúster de stage

**Qué pasó.** La API de Kubernetes de stage no está abierta a Internet, solo a Jenkins por la red privada. Probé la opción de túnel por AWS SSM, pero mi usuario no tiene ese permiso (`AccessDenied`).

**Cómo se resolvió.** Usé SSH al servidor de stage. Mi compañero autorizó mi IP en el firewall y registró mi llave pública en el servidor.

### Problema 4.5: la IP de la universidad cambia sola

**Qué pasó.** Al principio el SSH llegaba al servidor y un rato después daba `Connection timed out`. Mi IP pública había cambiado de `200.3.192.42` a `200.3.193.225`, y el firewall solo tenía autorizada la primera.

**Por qué.** La red de la universidad sale a Internet por varias IP y las va rotando.

**Cómo se resolvió.** Mi compañero autorizó el rango completo de salida de la universidad (`200.3.192.0/23`) en vez de una sola IP. Si me conecto desde la casa, hay que agregar esa otra IP.

### Problema 4.6: la llave SSH pedía una contraseña que no recordaba

**Qué pasó.** Con la red ya arreglada, el servidor aceptaba mi llave (`Server accepts key`), pero la conexión igual fallaba. Mi llave privada tenía passphrase, y yo no me acordaba de ella.

**Cómo se resolvió.** Generé una llave nueva solo para stage (`id_ed25519_stage`) y le pasé la parte pública a mi compañero para que la registrara. Nunca se comparte la llave privada, solo el archivo `.pub`.

**Lección.** Antes de pedir acceso, conviene revisar que la llave sí funciona con `ssh-keygen -y -f llave`.

### Problema 4.7: PowerShell se comía las comillas

**Qué pasó.** Para crear un usuario en la base de datos de stage pasé un comando por SSH. PostgreSQL respondió `role "root" does not exist`.

**Por qué.** Windows PowerShell 5.1 elimina las comillas dobles internas cuando le pasa argumentos a `ssh`. La variable `$POSTGRES_USER` llegaba vacía, así que psql intentaba entrar como `root`.

**Cómo se resolvió.** Envolví todo el comando en comillas dobles por fuera y simples por dentro, y escapé el `$` con la comilla invertida (`` `$POSTGRES_USER ``) para que PowerShell no tratara esa variable como suya.

### Problema 4.8: la cuenta de pruebas no existía en stage

**Qué pasó.** El login con la cuenta de pruebas daba `401`. Al revisar la tabla `local_users` de stage, solo estaban los tres usuarios de la semilla original.

**Cómo se resolvió.** Con la aprobación del equipo, creé el usuario `e2e_survey` con rol `STUDENT`. El hash BCrypt de su contraseña lo generó mi compañero, así que la contraseña nunca quedó en el repositorio.

### Problema 4.9: stage no tenía ningún cuestionario

**Qué pasó.** El flujo de envío de encuestas no se podía probar: `GET /questionnaires/active` respondía `404` porque la tabla estaba vacía.

**Cómo se resolvió.** Creé un cuestionario de prueba con 3 preguntas de sí o no. Lo dejé como mejora en el informe: sembrarlo con una migración de Flyway, para que todo ambiente nuevo lo tenga.

### Problema 4.10: la portería rechazaba a todo el mundo

**Qué pasó.** Con un usuario sano, la validación respondía `RED` con el mensaje "Invalid or Expired Token".

**Primer diagnóstico (equivocado).** Pensé que era el error del punto 2.1, porque stage tiene imágenes anteriores a ese arreglo. Pero al marcar al usuario como `ACTIVE` en Redis, el error siguió.

**Causa real.** En `application.yml` de auth-service, `qr.expiration: 300` se suma como **milisegundos**, así que el QR dura 0,3 segundos y vence antes de que la portería lo valide. Se comprobó leyendo el token: la fecha de vencimiento era igual a la de emisión.

**Cómo se resolvió para la prueba.** Se puso `QR_EXPIRATION=60000` (60 segundos) en el Deployment de auth de stage. Es un ajuste temporal: el arreglo de fondo en el código quedó como hallazgo para corregir en otra rama.

**Lección.** Un primer diagnóstico que suena lógico no siempre es el correcto. Hay que comprobarlo con datos antes de escribirlo en un informe.

### Problema 4.11: una regla de ZAP iba a fallar siempre

**Qué pasó.** Puse como FAIL la regla de "cookie sin la marca `Secure`". Stage se sirve por HTTP y no por HTTPS, así que cualquier cookie la habría activado y el pipeline nunca habría pasado.

**Cómo se resolvió.** Esa regla quedó como advertencia (WARN), con una nota de que vuelve a FAIL cuando el Ingress tenga TLS.

### Resultado de la HU-21

Con todo lo anterior resuelto:

- **Locust cumplió los 7 objetivos declarados:** 5 249 peticiones con 0 fallos, p95 de la portería en 240 ms y 17,5 peticiones por segundo.
- **ZAP terminó solo con advertencias:** faltan cabeceras de seguridad en nginx. No hubo alertas de riesgo alto.

El detalle está en [`docs/operaciones/hu-21-pruebas-avanzadas.md`](../../operaciones/hu-21-pruebas-avanzadas.md).

---

## 5. Buenas prácticas de seguridad

- **Credenciales fuera del repositorio.** Las credenciales de AWS y de la cuenta de pruebas se configuran directamente en la terminal (`aws configure`, `Read-Host -AsSecureString`) o en un archivo local fuera del repositorio, y se pasan a los contenedores como variables de entorno o con `--env-file`, nunca como argumentos de comandos.
- **Cambios en ambientes compartidos.** El usuario de pruebas, el cuestionario y el ajuste del QR en stage se hicieron con permiso del equipo y quedaron anotados en el informe para poder deshacerlos.

## 6. Resumen de lecciones

1. **Leer el error completo antes de cambiar algo.** Muchas veces la causa está en la última línea del mensaje (`role "root"`, `cp1252`, `Server accepts key`).
2. **En Windows hay tres fuentes de problemas que se repiten:** el certificado de Avast, la codificación de la consola y las comillas de PowerShell.
3. **Probar en el ambiente real encuentra errores que las pruebas locales no ven.** Ejemplos: la vida del QR, la falta del cuestionario y la cuenta inexistente.
4. **Comprobar un diagnóstico con datos** antes de darlo por cierto.
5. **La IA ayuda a entender y destrabar, pero la decisión y la responsabilidad son mías:** qué se cambia, qué se sube y a quién se le pide permiso.
