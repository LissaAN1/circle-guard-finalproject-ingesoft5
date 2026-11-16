# Patrón de resiliencia: Circuit Breaker y Retry con Resilience4j

**Historia:** HU-14 · **Épica:** E7 Patrones de diseño y resiliencia · **Entregable:** E2.4
**Servicios:** `circleguard-auth-service` y `circleguard-dashboard-service`

## 1. Problema

CircleGuard tiene dos llamadas HTTP síncronas entre servicios:

| Llamada | Cliente | Para qué | Qué pasaba si el servicio destino fallaba |
|---|---|---|---|
| auth → identity | `IdentityClient` | Obtener el `anonymousId` del usuario durante el login (`POST /api/v1/identities/map`). | La excepción llegaba al `LoginController` como un `500` genérico. Sin timeouts, un identity colgado bloqueaba el hilo del login indefinidamente. |
| dashboard → promotion | `PromotionClient` | Leer las estadísticas de salud del campus y por departamento (`GET /api/v1/health-status/stats[...]`). | Cada petición esperaba el fallo completo de promotion antes de responder; con promotion caído, todas las peticiones del dashboard pagaban esa espera. |

Ambos clientes usaban `new RestTemplate()`, sin timeouts ni reintentos. Una falla del servicio destino se
propagaba a cada petición y seguía cargando a un servicio que ya estaba degradado.

## 2. Solución

Se aplican dos patrones de Resilience4j a cada llamada, configurados por instancia (`identity` y `promotion`):

- **Retry:** reintenta las fallas transitorias (hasta 3 intentos con backoff exponencial: 200 ms y 400 ms
  en auth; 300 ms y 600 ms en dashboard).
- **Circuit Breaker:** observa los últimos 10 intentos. Cuando hay al menos 5 y el 50 % o más falló, el
  circuito se **abre**. Mientras está abierto, las llamadas se rechazan de inmediato sin contactar el
  servicio. Tras el tiempo de espera (15 s en auth, 30 s en dashboard) pasa a **semiabierto**, deja pasar 2
  llamadas de prueba y, si tienen éxito, se **cierra**.
- **Fallback:** la respuesta cuando no hay más que hacer.
  - En **auth** no existe un valor seguro: sin `anonymousId` no se puede emitir el token. El fallback
    lanza `IdentityServiceUnavailableException` y el login responde **503** con `Retry-After: 15`, en
    lugar de un `500` genérico.
  - En **dashboard**, que es de solo lectura, el fallback devuelve una respuesta degradada
    (`{"error": "Service unavailable", "degraded": true, "timestamp": ...}`) que conserva el contrato
    anterior. La HU-16 (cache-aside) la reemplazará por el último valor almacenado.
- **Timeouts:** cada cliente tiene su `RestTemplate` con timeouts de conexión y de lectura
  (`IdentityClientConfig` y `PromotionClientConfig`). Sin ellos, el Circuit Breaker nunca vería las fallas
  por cuelgue.

```text
LoginController ─▶ Retry ─▶ CircuitBreaker ─▶ RestTemplate (timeouts) ─▶ identity-service
                     │            │
                     │            └─ abierto: CallNotPermittedException (sin petición)
                     └─ intentos agotados o circuito abierto ─▶ fallback ─▶ 503
```

Resilience4j aplica el Retry por fuera del Circuit Breaker. Por eso cada intento queda registrado en el
circuito y el fallback se declara solo en `@Retry`: así se ejecuta después de los reintentos y no antes.
`CallNotPermittedException` no está en la lista de reintentos, de modo que un circuito abierto falla
rápido, sin esperar el backoff.

### 2.1 Qué cuenta como falla

Solo las fallas de infraestructura abren el circuito y se reintentan: `ResourceAccessException`
(conexión rechazada, timeout) y `HttpServerErrorException` (5xx). Un **4xx** es un error del llamador, no
un servicio enfermo: no se reintenta, no suma al porcentaje de fallas y se propaga igual que antes (en auth
se relanza la excepción; en dashboard se devuelve la respuesta degradada, como hacía el cliente original).

### 2.2 Configuración

La configuración vive en `src/main/resources/resilience4j.yml` de cada servicio y se importa desde
`application.yml` (`spring.config.import`). Las pruebas importan ese mismo archivo, así que verifican los
valores reales. Cada valor puede sobrescribirse por ambiente con variables de entorno, sin reconstruir la
imagen:

| Variable | Valor por defecto |
|---|---|
| `IDENTITY_CONNECT_TIMEOUT` / `IDENTITY_READ_TIMEOUT` | `2s` / `3s` |
| `PROMOTION_CONNECT_TIMEOUT` / `PROMOTION_READ_TIMEOUT` | `2s` / `5s` |
| `RESILIENCE4J_CIRCUITBREAKER_INSTANCES_IDENTITY_WAITDURATIONINOPENSTATE` | `15s` |
| `RESILIENCE4J_CIRCUITBREAKER_INSTANCES_PROMOTION_WAITDURATIONINOPENSTATE` | `30s` |

## 3. Trade-offs

| A favor | En contra |
|---|---|
| Un servicio caído ya no arrastra a quien lo llama: con el circuito abierto, la respuesta es inmediata. | Durante la ventana abierta (15 s o 30 s) se rechazan llamadas aunque el servicio ya se haya recuperado. |
| Se deja de enviar tráfico a un servicio degradado, lo que le da margen para recuperarse. | Los reintentos multiplican hasta por 3 la carga sobre un servicio que empieza a fallar; el backoff y el circuito la limitan. |
| El cliente recibe un error claro y temporal (503 con `Retry-After`) en lugar de un 500 genérico. | Reintentar solo es seguro en operaciones idempotentes. `POST /identities/map` lo es (la misma identidad siempre da el mismo `anonymousId`) y las estadísticas son `GET`; una operación nueva que no lo sea no debe reutilizar esta configuración. |
| El dashboard sigue respondiendo con promotion caído. | La respuesta degradada no tiene datos; hace falta la HU-16 para servir el último valor conocido. |
| Umbrales, tiempos y timeouts se ajustan por variable de entorno. | Hay más parámetros que calibrar; valores mal elegidos abren el circuito por ruido (muy sensibles) o no lo abren nunca (muy laxos). `minimum-number-of-calls: 5` evita que una sola falla lo abra. |

**Decisiones explícitas:**

- **No se registra el health indicator del circuito en Actuator.** Con el circuito abierto, Resilience4j
  marcaría `/actuator/health` de auth como `DOWN`. El healthcheck de Docker Compose y la verificación del
  despliegue (`deploy-remote.sh`) reiniciarían o revertirían auth por una falla que es de identity. El
  estado del circuito se expondrá como métrica con la observabilidad (HU-17).
- **El circuito es por instancia del servicio.** Cada réplica de auth decide por su cuenta. Es lo esperado
  en el patrón, pero con varias réplicas el circuito tarda un poco más en abrirse en todas.

## 4. Evidencia y pruebas

Las pruebas inyectan fallas en el servicio destino con `MockRestServiceServer`. Los aspectos de
Resilience4j se ejecutan de verdad: un contexto Spring mínimo carga AOP, las auto-configuraciones de
Circuit Breaker y Retry, y el `resilience4j.yml` de producción.

| Prueba | Qué demuestra |
|---|---|
| `IdentityClientResilienceTest` (auth, 5 casos) | Con identity respondiendo 500: tras 5 intentos fallidos el circuito pasa a `OPEN`, la siguiente llamada se rechaza sin petición (`CallNotPermittedException`) y solo 5 peticiones llegan a identity. También verifica que se recupera en semiabierto, que un fallo transitorio se reintenta con éxito y que un 4xx no se reintenta ni se cuenta. |
| `PromotionClientResilienceTest` (dashboard, 6 casos) | Lo mismo para promotion, con la respuesta degradada como fallback, y que ambas consultas de estadísticas comparten el mismo circuito. |
| `LoginControllerTest#shouldReturn503WhenIdentityServiceIsUnavailable` | El login responde 503 con `Retry-After` y no emite token cuando el fallback se activa. |

```bash
./gradlew :services:circleguard-auth-service:test --tests '*IdentityClientResilienceTest'
./gradlew :services:circleguard-dashboard-service:test --tests '*PromotionClientResilienceTest'
```

Las pruebas no llevan la etiqueta `integration`: corren en la etapa **Test** del pipeline, sin Docker, y
su informe JUnit se publica en Jenkins con el resto de las pruebas unitarias.

### 4.1 Demostración en un ambiente

En el servidor de un ambiente con Docker Compose (auth sí se despliega; dashboard se desplegará en la
Parte 2). El login se invoca a través del proxy del cliente web, publicado en `127.0.0.1:80`:

```bash
# 1. Detener identity-service
docker compose stop identity

# 2. Repetir el login: los dos primeros responden 503 tras los reintentos y, una vez abierto el
#    circuito, la respuesta 503 es inmediata (docker compose logs auth muestra "circuit is open").
for i in 1 2 3 4; do
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -X POST http://127.0.0.1/auth/api/v1/auth/login \
    -H 'Content-Type: application/json' -d '{"username":"<usuario>","password":"<clave>"}'
done

# 3. Levantar identity y esperar 15 s: el circuito pasa a semiabierto y el login vuelve a responder 200.
docker compose start identity
```

## 5. Archivos

| Archivo | Contenido |
|---|---|
| `services/circleguard-auth-service/src/main/java/com/circleguard/auth/client/IdentityClient.java` | Anotaciones `@CircuitBreaker` y `@Retry`, y el fallback. |
| `.../auth/client/IdentityClientConfig.java` | `RestTemplate` con timeouts. |
| `.../auth/client/IdentityServiceUnavailableException.java` | Excepción del fallback que se traduce a 503. |
| `.../auth/controller/LoginController.java` | Respuesta 503 con `Retry-After`. |
| `services/circleguard-auth-service/src/main/resources/resilience4j.yml` | Configuración de la instancia `identity`. |
| `services/circleguard-dashboard-service/src/main/java/com/circleguard/dashboard/client/PromotionClient.java` | Anotaciones y fallback degradado. |
| `.../dashboard/client/PromotionClientConfig.java` | `RestTemplate` con timeouts. |
| `services/circleguard-dashboard-service/src/main/resources/resilience4j.yml` | Configuración de la instancia `promotion`. |
