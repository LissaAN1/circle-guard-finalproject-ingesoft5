# Patrón cache-aside en dashboard con Redis

**Historia:** HU-16 · **Épica:** E7 Patrones de diseño y resiliencia · **Entregable:** E2.4
**Servicio:** `circleguard-dashboard-service` · **Relacionado:** HU-14 ([Circuit Breaker y Retry](resiliencia-circuit-breaker.md))

## 1. Problema

El dashboard muestra las estadísticas de salud del campus y por departamento. Cada consulta llamaba a
promotion-service (`GET /api/v1/health-status/stats[...]`), que calcula los totales con una consulta de
agregación sobre todos los usuarios en Neo4j. Eso generaba dos problemas:

- **Carga repetida.** Varias personas mirando el tablero piden los mismos totales cada pocos segundos, y
  promotion los recalcula cada vez, aunque cambian poco.
- **Sin datos cuando promotion falla.** Con la HU-14, si promotion estaba caído el dashboard respondía
  rápido, pero con una respuesta degradada y sin datos (`{"error": "Service unavailable", "degraded": true}`).

## 2. Solución

Se aplica **cache-aside** (carga perezosa) en Redis con `PromotionStatsCache`, que se ubica entre
`AnalyticsService` y `PromotionClient`:

```text
AnalyticsService ─▶ PromotionStatsCache ─┬─▶ Redis (lectura)              1. ¿hay entrada fresca? → responder
                                          ├─▶ PromotionClient (HU-14) ─▶ promotion-service
                                          │        Retry ─▶ CircuitBreaker ─▶ RestTemplate
                                          └─▶ Redis (escritura)           2. guardar la respuesta y su hora
                                                                          3. promotion no disponible → último valor
```

1. **Leer primero de la caché.** Si en Redis hay una entrada con menos de `fresh-ttl` (60 s), se responde
   con ella y **no se llama a promotion**.
2. **Si no hay entrada o ya no está fresca**, se llama a promotion a través de `PromotionClient`, que
   mantiene el Retry y el Circuit Breaker de la HU-14. Si la respuesta es válida, se guarda en Redis junto
   con la hora en que se leyó (`cachedAt`).
3. **Si promotion no está disponible** (el cliente devuelve su respuesta degradada porque se agotaron los
   reintentos o el circuito está abierto), se responde con el **último valor almacenado**, marcado con
   `stale: true` y `cachedAt`. Para eso, cada entrada se conserva en Redis durante `stale-ttl` (24 h), mucho
   más que el tiempo en que se considera fresca.
4. Si no hay ningún valor guardado, se mantiene la respuesta degradada de la HU-14.

Ejemplo de respuesta con promotion caído:

```json
{ "totalUsers": 120, "confirmedCount": 3, "stale": true, "cachedAt": "2026-11-16T15:00:00Z" }
```

El cliente puede mostrar que el dato es de esa hora. En las consultas por departamento se guardan los
valores sin filtrar, y el filtro de k-anonimato (`KAnonymityFilter`) se aplica en cada respuesta, también
a un valor `stale`.

### 2.1 Detalles

| Tema | Decisión |
|---|---|
| Llaves | `dashboard:promotion-stats:campus` y `dashboard:promotion-stats:department:<departamento>`. |
| Valor | JSON con `cachedAt` (instante ISO-8601) y `data` (las estadísticas tal como las devolvió promotion). |
| Frescura | Se calcula con `cachedAt` y el reloj del servicio, no con el TTL de Redis. Así una sola entrada sirve para responder rápido (fresca) y para el respaldo (vieja). |
| Expiración en Redis | `stale-ttl`. Pasado ese tiempo la entrada desaparece y no se sirven datos de más de un día. |
| Qué no se guarda | La respuesta degradada de promotion. Si se guardara, ocultaría el último valor bueno. |
| Health check | `management.health.redis.enabled: false`: si se agrega Actuator, Redis caído no debe marcar el dashboard como `DOWN` ni hacer que las sondas de Kubernetes lo reinicien. |
| Redis caído | La caché es una optimización, no una dependencia. Un error de Redis (`DataAccessException`) se registra y la consulta va a promotion como antes de esta historia. Los timeouts de Redis son de 500 ms para no retrasar el dashboard. Una entrada ilegible se ignora. |

### 2.2 Configuración

En `application.yml` del dashboard. Se pueden cambiar por ambiente con variables de entorno, sin
reconstruir la imagen:

| Variable | Valor por defecto | Para qué |
|---|---|---|
| `DASHBOARD_CACHE_FRESH_TTL` | `60s` | Tiempo en que una entrada se responde sin llamar a promotion. |
| `DASHBOARD_CACHE_STALE_TTL` | `24h` | Tiempo que se conserva el último valor para el respaldo. Debe ser mayor o igual que el anterior. |
| `SPRING_DATA_REDIS_HOST` / `SPRING_DATA_REDIS_PORT` | `localhost` / `6379` | Redis, el mismo que usan gateway y promotion. |
| `REDIS_PASSWORD` | vacío | Contraseña de Redis; en Kubernetes llega del Secret `circleguard-secrets` (`infra/k8s/base/apps/dashboard.yaml`). |

## 3. Trade-offs

| A favor | En contra |
|---|---|
| Una consulta repetida dentro de los 60 s no llega a promotion: menos carga sobre promotion y Neo4j. | Los datos pueden tener hasta 60 s de atraso. Para un tablero de tendencias es aceptable; para una decisión individual de acceso no lo sería (esa sigue en gateway, que lee el estado actualizado en Redis). |
| Con promotion caído, el dashboard sigue mostrando datos reales, aunque viejos, y lo indica con `stale` y `cachedAt`. | Un valor `stale` puede no reflejar un brote reciente. Por eso se marca y se limita a 24 h. |
| Se complementa con la HU-14: con el circuito abierto, el último valor se sirve sin esperar a promotion. | Se agrega Redis como pieza más del dashboard (configuración, contraseña, memoria). |
| Si Redis falla, el servicio funciona como antes. | Con Redis caído no hay respaldo: si además falla promotion, solo queda la respuesta degradada. |
| Llaves simples por consulta, fáciles de inspeccionar con `redis-cli`. | Cache-aside no invalida al cambiar los datos: un cambio en promotion se ve cuando vence el TTL. Invalidar por eventos de Kafka sería más exacto, pero más complejo de lo que el tablero necesita. |
| En la primera consulta de cada llave (caché fría) no hay ganancia. | Varias réplicas que encuentran la llave vencida al mismo tiempo pueden llamar todas a promotion una vez (sin bloqueo). Con un TTL de 60 s y pocas réplicas el impacto es bajo. |

## 4. Evidencia y pruebas

Las pruebas no necesitan un Redis real: usan un doble en memoria (`InMemoryRedis`) y un reloj que se
adelanta a mano (`MutableClock`) para vencer el TTL. No llevan la etiqueta `integration`, así que corren
en la etapa **Test** del pipeline.

| Prueba | Qué demuestra |
|---|---|
| `PromotionStatsCacheFailureInjectionTest` (3 casos) | Con el `PromotionClient` real, los aspectos de Resilience4j de la HU-14 y un promotion simulado con `MockRestServiceServer`: **(1)** una consulta repetida antes del TTL hace una sola petición a promotion; **(2)** con promotion detenido (cada reintento recibe *connection refused*), el dashboard responde con el último valor almacenado, `stale: true` y su `cachedAt`; **(3)** con el circuito abierto, el último valor se sirve sin ninguna petición a promotion. |
| `PromotionStatsCacheTest` (9 casos) | Frescura antes y después del TTL, respaldo con el último valor, que la respuesta degradada no se guarde, la expiración de 24 h en Redis, llaves separadas por departamento, Redis caído, entrada ilegible y TTL inválidos. |
| `AnalyticsServiceTest` (2 casos) | Las estadísticas salen de la caché y el k-anonimato se aplica también a un valor `stale`. |

```bash
./gradlew :services:circleguard-dashboard-service:test --tests '*PromotionStatsCache*'
```

### 4.1 Demostración manual

El dashboard no está en el Docker Compose de los ambientes; en Kubernetes (HU-11) su Deployment recibe la
conexión a Redis por variables de entorno. Para verlo funcionar en local con Redis y promotion levantados:

```bash
# 1. Primera consulta: llega a promotion y se guarda en Redis.
curl -s http://localhost:8084/api/v1/analytics/summary
redis-cli GET dashboard:promotion-stats:campus     # {"cachedAt":"...","data":{...}}

# 2. Repetir antes de 60 s: misma respuesta y ningún registro nuevo en el log de promotion.
curl -s http://localhost:8084/api/v1/analytics/summary

# 3. Detener promotion y esperar más de 60 s: la respuesta trae "stale": true y "cachedAt".
curl -s http://localhost:8084/api/v1/analytics/summary
```

## 5. Archivos

| Archivo | Contenido |
|---|---|
| `services/circleguard-dashboard-service/src/main/java/com/circleguard/dashboard/cache/PromotionStatsCache.java` | Lectura de Redis, llamada a promotion, escritura y respaldo con el último valor. |
| `.../dashboard/cache/CacheConfig.java` | Reloj del servicio (reemplazable en pruebas). |
| `.../dashboard/service/AnalyticsService.java` | Usa la caché en lugar de llamar a `PromotionClient` directamente. |
| `services/circleguard-dashboard-service/src/main/resources/application.yml` | Conexión a Redis y TTL de la caché. |
| `services/circleguard-dashboard-service/build.gradle.kts` | Dependencia `spring-boot-starter-data-redis`. |
| `infra/k8s/base/apps/dashboard.yaml` | Variables de conexión a Redis en el Deployment. |
