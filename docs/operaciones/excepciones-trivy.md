# Excepciones del escaneo Trivy (imágenes)

El gate de Trivy sigue bloqueando cualquier hallazgo **CRITICAL** en las imágenes. La única excepción vigente está en
[`ci/trivy/images.trivyignore`](../../ci/trivy/images.trivyignore) y se aplica solo al escaneo de imágenes
(`ci/scripts/trivy-run.sh images`, mediante `--ignorefile`).

## Contexto

El pipeline #55 de `dev` llegó a Trivy Images con Spring Boot 3.5.16 y Tomcat 10.1.62 (que ya eliminaron 9 de los 11
hallazgos del #53). Quedaron dos hallazgos que **Trivy clasifica como CRITICAL** en
`org.springframework:spring-webmvc 6.2.19`:

| CVE | Condición para explotarla | ¿Aplica a CircleGuard? |
|:---|:---|:---|
| CVE-2026-47884 (SSRF/RCE) | `XsltView` con un mapeo `/**` que renderiza vistas sin nombre explícito | No: ningún servicio usa `XsltView`, `ViewResolver` ni `ModelAndView`. Son APIs REST (JSON). |
| CVE-2026-47890 (corrupción de stream SSE) | Server-Sent Events con fragmentos de vista | No: ningún servicio usa `SseEmitter` ni `text/event-stream`. |

### Severidad

La clasificación CRITICAL es la que reporta Trivy a partir de bases de vulnerabilidades (GitHub Advisory publica
CVSS 9.8). No debe leerse como la severidad que asigna el proveedor: el aviso de Spring para CVE-2026-47884 la
califica como **Medium** porque depende de una configuración concreta. Como el gate de CircleGuard se basa en Trivy,
se trata como CRITICAL y por eso hace falta la excepción documentada.

### Versiones corregidas

Spring Framework 6.2.19 es la última versión pública de la línea 6.2. La alternativa de código abierto es Spring
Framework 7.0.9, que exige migrar a Spring Boot 4. Las correcciones para la línea 6.x parecen ofrecerse solo mediante
soporte comercial; el número exacto de esa versión (por ejemplo 6.2.20) no está verificado en una fuente pública, así
que no se asume.

`notification` usa Freemarker únicamente para componer el texto de los mensajes (`TemplateService`); no es una vista web.

## Controles

- Solo se ignoran esas dos CVE, no una severidad ni un paquete completo.
- El archivo se llama `images.trivyignore` a propósito. Trivy carga `./.trivyignore` automáticamente en cualquier
  escaneo, así que con ese nombre las excepciones llegarían también a IaC y secretos. Con otro nombre solo se aplican
  donde se pasa `--ignorefile` (imágenes).
- Cada entrada lleva `exp:2026-12-23`: pasada esa fecha Trivy deja de ignorarla y vuelve a bloquear.
- `ci/tests/test_platform_security.py` (`TrivyIgnoreContract`) verifica que solo están esas CVE, que cada fecha existe,
  está en el futuro y a no más de 45 días (el test falla antes del vencimiento para forzar la revisión), que no existe
  un `.trivyignore` en la raíz y que solo el modo `images` usa `--ignorefile`, sin quitar el umbral CRITICAL.

## Plan

Migrar a Spring Boot 4 (Spring Framework 7.0.9 o superior) antes de la fecha de caducidad y retirar el archivo.
