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

- **FAIL:** cookies sin `HttpOnly` (10010), información sensible en la URL (10024) y divulgación de datos personales (10062). En un sistema de salud con identidad anónima, cualquiera de ellas es un defecto que no debe llegar a producción.
- **WARN explícito:** cookie sin `Secure` (10011). Stage se sirve por HTTP, así que con FAIL bloquearía siempre que haya una cookie; pasa a FAIL cuando el Ingress tenga TLS.
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

Ejecución manual del 2026-11-20, antes del merge, con los mismos comandos y las mismas imágenes que usan las etapas de Jenkins. No corresponde a un build del pipeline. Se llegó al Service `web` de stage por un túnel SSH al servidor (`kubectl port-forward service/web 8783:80`).

| Dato | Valor |
|:---|:---|
| Fecha | 2026-11-20. Locust de 10:37:53 a 10:42:52 y ZAP a las 10:44 (UTC−5) |
| Imágenes desplegadas | las 9 en `1.0.0-ci.37.16dffba`, anterior a los PR #57 y #58 |
| Clúster | 2 nodos Ready y 15 pods Running 1/1 en `circleguard-stage` antes de la prueba |
| Herramientas | `locustio/locust:2.32.4` y `zaproxy/zap-stable:2.16.0` |
| Carga | la de `targets.json`: 20 usuarios, 2 por segundo, 5 minutos |

**Datos de prueba y ajustes en stage.** Sin ellos, los dos flujos no podían ejecutarse (hallazgos 6 y 7):

- **Cuestionario activo.** Stage respondía 404 en `GET /form/api/v1/questionnaires/active`. Se creó `Autoevaluacion diaria (HU-21)` en `circleguard_form`, con 3 preguntas `YES_NO` (fiebre, tos o dolor de garganta, contacto con un caso confirmado).
- **Estado de la cuenta de E2E.** La clave `user:status:<anonymousId de e2e_survey>` se puso en `ACTIVE` en Redis, con 3 h de vida. Después se comprobó que no hacía falta (hallazgo 6).
- **Vida del QR.** El Deployment `auth` recibió `QR_EXPIRATION=60000`. Sin ese ajuste, el QR caducaba antes de validarse y toda validación devolvía RED. Es un ajuste temporal de stage hasta corregir el código.

**Locust** (`ci/reports/performance/summary.md`): veredicto **CUMPLE**. Hubo 5 249 peticiones y 0 fallos; `locust_failures.csv` quedó vacío.

| Alcance | Métrica | Objetivo | Resultado | Cumple |
|:---|:---|:---|:---|:---|
| gate: qr generate | p95 | ≤ 500 ms | 430 ms | sí |
| gate: validate | p95 | ≤ 300 ms | 240 ms | sí |
| survey: active questionnaire | p95 | ≤ 500 ms | 390 ms | sí |
| survey: submit | p95 | ≤ 800 ms | 370 ms | sí |
| Global | p95 | ≤ 800 ms | 390 ms | sí |
| Global | throughput | ≥ 8 req/s | 17,54 req/s | sí |
| Global | tasa de error | ≤ 1 % | 0 % | sí |

La mediana de todas las peticiones fue de 100 ms. Los 20 `auth: login` del arranque no tienen objetivo y tuvieron un p95 de 950 ms.

**OWASP ZAP baseline** (`ci/reports/zap/zap-report.html`): código de salida **2**, solo advertencias. El conteo fue FAIL-NEW 0, WARN-NEW 5, IGNORE 1 y PASS 51.

| Riesgo ZAP | Alertas | Detalle |
|:---|:---|:---|
| Alto | 0 | — |
| Medio | 2 | CSP no definida (10038, 7 URL). Falta la cabecera anti-clickjacking (10020, 4 URL) |
| Bajo | 3 | Cabecera `Server` con la versión de nginx (10036, 12). Falta `X-Content-Type-Options` (10021, 11). Marcas de tiempo (10096, 16; regla IGNORE, falso positivo del bundle de Expo) |
| Informativo | 1 | Comentarios sospechosos en el bundle JS (10027, 1) |

No se activó ninguna regla FAIL: no hubo cookies sin `HttpOnly`, datos sensibles en la URL ni datos personales. La regla 10011 (cookie sin `Secure`) tampoco apareció.

## 6. Interpretación y mejoras propuestas

**Interpretación.** Con la carga declarada, stage cumple los siete objetivos con margen. La validación en portería, que es la ruta más sensible, tuvo un p95 de 240 ms frente a un objetivo de 300 ms. El throughput duplicó el mínimo. No hubo errores. El margen depende del escalado: durante la prueba el HPA llevó auth de 1 a 3 réplicas y form de 1 a 2 (`kubectl get hpa`, CPU de auth al 60 % y de form al 70 % de su objetivo). En seguridad no hay alertas altas ni reglas FAIL. Lo que ZAP encontró son cabeceras que faltan en nginx.

Hallazgos esperados:

1. **Cabeceras de seguridad: se confirma.** ZAP reporta que faltan CSP (10038) y la protección anti-clickjacking (10020) como riesgo medio, y que falta `X-Content-Type-Options` (10021) como riesgo bajo. La única cabecera relevante que envía `GET /` es `Server: nginx/1.27.5`, que ZAP también reporta (10036). **Mejora:** agregar `Content-Security-Policy`, `X-Frame-Options: DENY` (o `frame-ancestors` en la CSP) y `X-Content-Type-Options: nosniff` en el bloque `server` de `mobile/nginx.conf`, y además `server_tokens off;`.
2. **CORS abierto en form-service: se confirma.** ZAP no lo cubre, así que se comprobó a mano. Un preflight a `/form/api/v1/surveys` con `Origin: https://evil.example` recibe `Access-Control-Allow-Origin: *`, y el mismo preflight a auth-service recibe 403. El código es el mismo en `HEAD`: cuatro controladores con `@CrossOrigin(origins = "*")`. **Mejora:** usar en form-service la lista `app.cors.allowed-origins` de auth-service.
3. **Caché del cuestionario activo: se descarta.** `survey: active questionnaire` tuvo un p95 de 390 ms frente al objetivo de 500, con una mediana de 100 ms. Con esta carga no hace falta caché.
4. **Escalado tardío: no se confirma.** El HPA escaló en el primer minuto. El pico de p95 del arranque (1,3 s) coincide con los inicios de sesión y con las réplicas nuevas en frío. Además, auth acababa de reiniciarse por el ajuste de `QR_EXPIRATION`. Hubo un segundo pico, de 10:40:50 a 10:41:15 (p95 de unos 750 ms, mediana de 400 ms y throughput bajando a 13 req/s), que no coincide con ningún evento de escalado registrado. Los datos no alcanzan para atribuirlo, así que no se propone cambiar el HPA.
5. **Pool de conexiones: no se evaluó.** Las réplicas no pasaron de 3 en auth ni de 2 en form, y no se midieron las conexiones a PostgreSQL. No hay evidencia en ningún sentido.

Hallazgos del despliegue real:

6. **El QR caduca antes de validarse.** Stage corre `1.0.0-ci.37.16dffba`, anterior a los PR #57 y #58, y toda validación devolvía RED `Invalid or Expired Token`. La causa no es una clave `user:status` ausente: con esa imagen, una clave ausente da GREEN, y con `ACTIVE` en Redis la validación siguió en RED. La causa es que `qr.expiration: 300` de auth-service se suma como milisegundos en `QrTokenService` (`currentTimeMillis() + expiration`). Las claims del token tenían `exp − iat = 0 s`, y la validación llegó 440 ms después, con el QR ya vencido. `HEAD` tiene el mismo valor, así que desplegar imágenes posteriores a #57 y #58 no lo corrige. Para medir se aplicó `QR_EXPIRATION=60000` en stage; después, el QR dura 60 s y el gate responde GREEN. **Mejora:** corregir en auth-service la unidad de `qr.expiration` (interpretarla en segundos o declarar `300000`), con una prueba que valide un QR recién emitido. Luego, quitar `QR_EXPIRATION` del Deployment de stage.
7. **Stage no tenía cuestionario activo.** `GET /form/api/v1/questionnaires/active` respondía 404, y el flujo de envío no se podía probar ni usar. Se creó uno de prueba. **Mejora:** sembrar un cuestionario por defecto con una migración de Flyway en form-service, para que todo ambiente nuevo lo tenga.

Mejoras propuestas, por prioridad: corregir la vida del QR (6), cerrar CORS en form-service (2), agregar cabeceras de seguridad en nginx (1) y sembrar el cuestionario con Flyway (7).
