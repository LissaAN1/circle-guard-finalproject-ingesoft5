# HU-17 — Métricas y alertas críticas con Prometheus (PI-26)

Prometheus y Alertmanager corren **dentro del namespace de cada ambiente** (`circleguard-dev|stage|prod`, HU-11) y se despliegan con `infra/k8s/observability.sh`. La configuración vive una sola vez en `observability/`.

## Métricas (PI-130)

Todos los módulos incluyen `spring-boot-starter-actuator` y `micrometer-registry-prometheus` (build raíz) y los 8 `application.yml` exponen `/actuator/prometheus` con histogramas de `http.server.requests`. El `SecurityConfig` de identity lo permite sin autenticación.

| Métrica | Origen | Consulta |
|:---|:---|:---|
| `circleguard_promotions_total{status}` | `HealthStatusService` (promotion) | promociones/min: `sum(rate(circleguard_promotions_total[1m])) * 60` |
| `circleguard_checkins_total{result}` | `LocationResolutionService` (promotion) | `sum by (result) (rate(circleguard_checkins_total[5m]))` |
| `circleguard_containment_duration_seconds{outcome}` | `HealthStatusService.updateStatus` | `histogram_quantile(0.95, sum by (le) (rate(circleguard_containment_duration_seconds_bucket[5m])))` |
| `resilience4j_circuitbreaker_state{name,state}` | HU-14 (auth, dashboard) | `resilience4j_circuitbreaker_state == 1` |

## Prometheus (PI-131)

- Descubre **pods** (`kubernetes_sd_configs`, rol `pod`, solo su namespace) y no Services: en prod hay 2 réplicas por servicio, y un target por Service mezclaría las métricas de ambas en cada lectura y rompería `rate()`.
- Solo toma los 8 servicios Spring Boot (`auth, identity, promotion, form, gateway, dashboard, file, notification`); `web` (Nginx) y el middleware no se leen.
- Etiquetas: `service` (`auth`), `application` (`circleguard-auth-service`), `pod`.
- RBAC de mínimo privilegio: un `Role` que solo permite `get/list/watch` de pods en su propio namespace.
- Sin Ingress: acceso por `kubectl port-forward` (el Ingress es de HU-12). Sin volumen persistente: la retención de 7 días se pierde si el pod se reinicia.

```bash
export KUBE_CONTEXT=circleguard-dev            # el script rechaza un contexto que no corresponda al ambiente
ALERT_WEBHOOK_URL='https://...' bash infra/k8s/observability.sh dev
kubectl --context circleguard-dev -n circleguard-dev port-forward svc/prometheus 9090 &
EXPECTED=8 bash observability/scripts/verify-targets.sh
```

La URL del webhook se guarda en el Secret `alertmanager-webhook` (creado por el script, nunca en el repositorio). Sin `ALERT_WEBHOOK_URL` las alertas se evalúan y se ven en Alertmanager, pero no se envían.

## Alertas (PI-132)

| Alerta | Severidad | Condición | Prueba real |
|:---|:---|:---|:---|
| `ServiceDown` | critical | un pod no responde (`up == 0`) o un servicio no tiene pods, durante 1 min | `fail-service-down.sh`: escala un Deployment a 0 |
| `HighErrorRate` | critical | más de 5 % de respuestas 5xx durante 2 min (con ≥ 0,1 req/s) | `fail-circuit-error-rate.sh`: identity a 0 y logins válidos contra auth (503) |
| `CircuitBreakerOpen` | critical | circuito de HU-14 abierto durante 1 min | el mismo script (el circuito `identity` de auth se abre) |
| `HighLatencyP95` | warning | p95 > 2 s durante 3 min | solo prueba unitaria |

`HighLatencyP95` no cuenta entre las 3 críticas probadas: en Kubernetes no hay forma limpia de provocar lentitud sin tumbar la salud del pod (el `/actuator/health` de los servicios incluye la base de datos, así que apagar PostgreSQL saca los pods de servicio y reinicia por liveness antes de que la alerta pueda dispararse).

```bash
# Pruebas unitarias de las reglas (sin clúster)
docker run --rm -v "$PWD/observability/prometheus:/p" -w /p/tests --entrypoint promtool prom/prometheus:v2.54.1 test rules circleguard-critical.test.yml

# Pruebas de falla real (cada script restaura el estado al terminar)
ENVIRONMENT=dev SERVICE=auth bash observability/scripts/fail-service-down.sh
ENVIRONMENT=dev LOGIN_USER=<cuenta-ldap> LOGIN_PASSWORD=<clave> bash observability/scripts/fail-circuit-error-rate.sh
```

`fail-circuit-error-rate.sh` necesita una cuenta de prueba válida del LDAP, porque auth autentica antes de llamar a identity; con credenciales inválidas respondería 401 y no habría errores 5xx. Las credenciales viajan en un Secret temporal que el script borra.

## Evidencia (sin secretos)

1. `verify-targets.sh`: 8/8 servicios con todos sus pods `UP` en cada ambiente.
2. `verify-metrics.sh` tras generar actividad (cambio de estado en promotion, señal de ubicación).
3. Por alerta: captura de Prometheus (*Pending → Firing*), de Alertmanager y log del script con marcas de hora, más la recuperación.
4. Salida de `promtool test rules` y de `./gradlew test`.

## Pendientes y límites

- **Nada de esto se ha aplicado en un clúster real** (igual que HU-11): el criterio de los 8 servicios en `UP` se cierra al desplegar los ambientes.
- **HU-13:** el pipeline debe ejecutar `infra/k8s/observability.sh <ambiente>` después de `deploy.sh`.
- **Memoria:** Prometheus y Alertmanager agregan hasta ~640 MiB de límite al nodo único de `dev`; verificar que cabe junto a los 15 workloads de HU-11.
- Las alertas notifican por webhook; el correo de SNS de `observability` (Terraform) es otra vía y no sustituye a esta.
