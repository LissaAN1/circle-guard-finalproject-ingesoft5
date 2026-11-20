# HU-21: pruebas avanzadas en stage (Locust y OWASP ZAP)

Pruebas de rendimiento y de seguridad que el pipeline ejecuta sobre stage después del E2E y antes del plan y la aprobación de producción. Un objetivo incumplido o una regla FAIL de ZAP detiene la promoción.

```
Deploy Stage -> E2E Tests -> Performance STAGE -> ZAP Baseline STAGE -> Terraform Plan PROD -> Approve Prod
```

Las dos etapas solo corren en `main` con `CG_CD_PLATFORM=k8s`, porque llegan al Service `web` de stage con `kubectl port-forward` usando la credencial `kubeconfig-stage`.

## 1. Objetivos declarados antes de la prueba

Los objetivos están en [`tests/performance/targets.json`](../../tests/performance/targets.json) y se versionan con el código: cambiarlos requiere un PR, de modo que no se ajustan después de ver los resultados.

| Petición | Servicio | p95 objetivo |
|:---|:---|:---|
| `gate: qr generate` (`GET /auth/api/v1/auth/qr/generate`) | auth | ≤ 500 ms |
| `gate: validate` (`POST /gateway/api/v1/gate/validate`) | gateway + Redis | ≤ 300 ms |
| `survey: active questionnaire` (`GET /form/api/v1/questionnaires/active`) | form | ≤ 500 ms |
| `survey: submit` (`POST /form/api/v1/surveys`) | form + PostgreSQL + Kafka | ≤ 800 ms |

| Métrica global | Objetivo |
|:---|:---|
| p95 de todas las peticiones | ≤ 800 ms |
| Throughput | ≥ 8 peticiones/s |
| Tasa de error | ≤ 1 % |

Carga: 20 usuarios concurrentes, 2 nuevos por segundo, 5 minutos, con 1 a 3 s de espera entre tareas.

**Justificación.** La validación en portería es la ruta más sensible: un estudiante espera frente al torniquete, y la decisión solo lee una clave de Redis, por eso tiene el objetivo más estricto. El envío del cuestionario escribe en PostgreSQL y publica un evento, por eso tiene más margen. 20 usuarios representan una entrada de clase en una portería con varios lectores. La carga cabe en stage (1 servidor y 1 agente m7i-flex.large, con HPA de 1 a 3 réplicas) sin saturar el clúster que comparten los demás ambientes.

## 2. Escenarios de Locust

Archivo: [`tests/performance/locustfile.py`](../../tests/performance/locustfile.py). Cada usuario virtual inicia sesión una vez con la cuenta dedicada de E2E (`circleguard-stage-e2e-survey`) y repite dos tareas, en proporción 3 a 1:

1. **Validación de acceso.** Pide a auth un QR firmado y de vida corta, y lo valida en el gateway. La respuesta debe ser `valid: true` y `GREEN`. Un 200 con otra decisión cuenta como fallo.
2. **Envío de cuestionario.** Lee el cuestionario activo y lo envía respondiendo NO a todo. Así la carga no cambia el estado de salud de nadie ni dispara promociones de contagio en stage.

Los tokens, las contraseñas y los cuerpos de respuesta no se registran. Las credenciales llegan como variables de entorno, no como argumentos.

[`tests/performance/evaluate.py`](../../tests/performance/evaluate.py) lee `locust_stats.csv` y compara cada objetivo. Escribe `summary.md` y `summary.json`, y sale con 1 si algo no se cumple. Locust sale con 1 ante cualquier petición fallida, aunque sea una sola; por eso el veredicto lo da la tasa de error declarada y no el código de salida de Locust.

## 3. OWASP ZAP baseline

Script: [`ci/scripts/zap-run.sh`](../../ci/scripts/zap-run.sh), con la imagen `zaproxy/zap-stable:2.16.0`. El baseline recorre el sitio con el spider durante 3 minutos y aplica solo reglas pasivas: no envía ataques, así que es seguro contra un ambiente compartido.

| Código de salida | Significado | Efecto en el pipeline |
|:---|:---|:---|
| 0 | sin alertas | pasa |
| 2 | solo advertencias | pasa; el informe queda publicado |
| 1 | se activó una regla FAIL | falla y bloquea la promoción |
| 3 u otro | error del escáner | falla |

Reglas en [`ci/zap/rules.tsv`](../../ci/zap/rules.tsv):

- **FAIL:** cookies sin `HttpOnly` o `Secure` (10010, 10011), información sensible en la URL (10024) y divulgación de datos personales (10062). En un sistema de salud con identidad anónima, cualquiera de ellas es un defecto que no debe llegar a producción.
- **IGNORE:** divulgación de marcas de tiempo (10096). Es un falso positivo con los hashes del bundle de Expo.
- **WARN:** el resto, por defecto.

Publicación: Jenkins publica `HU-21 Locust` y `HU-21 OWASP ZAP` como informes HTML del build y archiva `ci/reports/performance/**` y `ci/reports/zap/**`.

## 4. Cómo ejecutarlo fuera de Jenkins

Con un kubeconfig que tenga el contexto `circleguard-stage`:

```bash
export KUBECONFIG=~/.kube/circleguard-stage E2E_USERNAME=... E2E_PASSWORD=...
bash tests/performance/run-k8s.sh stage   # informe en ci/reports/performance/
bash ci/scripts/zap-run.sh stage          # informe en ci/reports/zap/
```

Pruebas sin clúster: `python -m pytest ci/tests/test_hu21_pipeline.py`. Simulan docker, kubectl, curl y jq, y comprueban:

- el orden de las etapas;
- la evaluación de cada objetivo;
- que una advertencia de ZAP no bloquea y una regla FAIL sí;
- que un contexto de otro ambiente se rechaza;
- que la contraseña no aparece en los argumentos.

## 5. Resultados en stage

> Pendiente de la primera ejecución del pipeline en `main` con stage encendido. Copiar aquí `ci/reports/performance/summary.md` y el resumen de alertas de `zap-report.md`, con el número de build y la versión de las imágenes.

| Alcance | Métrica | Objetivo | Resultado | Cumple |
|:---|:---|:---|:---|:---|
| gate: validate | p95 | ≤ 300 ms | | |
| survey: submit | p95 | ≤ 800 ms | | |
| Global | p95 | ≤ 800 ms | | |
| Global | throughput | ≥ 8 req/s | | |
| Global | tasa de error | ≤ 1 % | | |

| Riesgo ZAP | Alertas | Ejemplos |
|:---|:---|:---|
| Alto | | |
| Medio | | |
| Bajo / informativo | | |

## 6. Interpretación y mejoras propuestas

> Completar con los resultados. Hallazgos que se esperan por la configuración actual, para confirmar o descartar:

- **Cabeceras de seguridad.** `mobile/nginx.conf` no envía `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options` ni `Permissions-Policy`. Es probable que ZAP lo reporte como advertencias de riesgo medio y bajo. Mejora: agregarlas en el bloque `server` de nginx o como Middleware de Traefik en el Ingress.
- **CORS abierto en form-service.** `@CrossOrigin(origins = "*")` en los controladores permite llamadas desde cualquier origen. Mejora: usar la misma lista `app.cors.allowed-origins` que auth-service.
- **Cuestionario activo.** Cada envío pide el cuestionario activo a PostgreSQL. Si su p95 es alto, conviene la misma caché en Redis que se usa en el dashboard (HU-16).
- **Escalado.** Si el p95 sube durante el arranque de la carga y baja después, el HPA reacciona tarde. Mejora: bajar el umbral de CPU o subir `minReplicas` en stage para gateway y form.
- **Pool de conexiones.** Con 3 réplicas por servicio, las conexiones a PostgreSQL se acercan al límite de 300 (hallazgo 5 de `hu-10-inventario-aws.md`). Mejora: fijar `hikari.maximum-pool-size` por servicio.
