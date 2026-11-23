# Excepciones del escaneo Trivy (imágenes)

El gate de Trivy sigue bloqueando cualquier hallazgo **CRITICAL** en las imágenes. La única excepción vigente está en
[`.trivyignore`](../../.trivyignore) y se aplica solo al escaneo de imágenes (`ci/scripts/trivy-run.sh images`).

## Contexto

El pipeline #55 de `dev` llegó a Trivy Images con Spring Boot 3.5.16 y Tomcat 10.1.62 (que ya eliminaron 9 de los 11
hallazgos del #53). Quedaron dos CRITICAL en `org.springframework:spring-webmvc 6.2.19`:

| CVE | Condición para explotarla | ¿Aplica a CircleGuard? |
|:---|:---|:---|
| CVE-2026-47884 (SSRF/RCE, CVSS 9.8) | `XsltView` con un mapeo `/**` que renderiza vistas sin nombre explícito | No: ningún servicio usa `XsltView`, `ViewResolver` ni `ModelAndView`. Son APIs REST (JSON). |
| CVE-2026-47890 (corrupción de stream SSE, CVSS 9.8) | Server-Sent Events con fragmentos de vista | No: ningún servicio usa `SseEmitter` ni `text/event-stream`. |

No existe una versión parcheada para Spring Framework 6.x (6.2.19 es la última). El arreglo solo está en Spring
Framework 7.0.9, es decir, Spring Boot 4.

`notification` usa Freemarker únicamente para componer el texto de los mensajes (`TemplateService`); no es una vista web.

## Controles

- Solo se ignoran esas dos CVE, no una severidad ni un paquete completo.
- Cada entrada lleva `exp:2026-12-23`: pasada esa fecha Trivy vuelve a bloquear.
- `ci/tests/test_platform_security.py` verifica que el archivo solo contiene esas CVE, que todas caducan y que el
  escaneo de IaC y de secretos no lo usan.

## Plan

Migrar a Spring Boot 4 (Spring Framework 7.0.9 o superior) antes de la fecha de caducidad y retirar el archivo.
