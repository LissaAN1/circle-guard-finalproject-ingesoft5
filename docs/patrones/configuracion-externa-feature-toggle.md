# Patrón de configuración externa y feature toggle

**Historia:** HU-15 · **Épica:** E7 Patrones de diseño y resiliencia · **Entregable:** E2.4
**Servicio:** `circleguard-gateway-service` · **Infraestructura:** `infra/k8s` (ConfigMap `circleguard-config`)

## 1. Problema

La configuración que cambia entre ambientes, o que el negocio quiere cambiar con el sistema en marcha, no
debe estar dentro de la imagen. Si lo está, cada cambio obliga a recompilar, generar una imagen nueva,
pasarla por el pipeline y desplegarla, aunque el código sea el mismo.

En CircleGuard, la regla de acceso del gateway estaba fija en el código: todo usuario `SUSPECT` o
`PROBABLE` era rechazado en la entrada (HU-07). Esa regla depende de la fase epidemiológica, que la decide
el equipo de salud de la universidad y no el equipo de desarrollo. Relajarla en una fase de bajo riesgo
habría exigido una versión nueva del gateway.

## 2. Solución

Se combinan dos patrones:

- **Configuración externa.** El servicio lee su configuración del entorno. En Kubernetes, la configuración
  no sensible de cada ambiente vive en el ConfigMap `circleguard-config` del overlay (`dev`, `stage`,
  `prod`) y los secretos en el Secret `circleguard-secrets`. La misma imagen sirve para los tres ambientes.
- **Feature toggle.** Un interruptor de configuración activa o desactiva un comportamiento sin cambiar el
  código desplegado. Es un *toggle* de operación (*ops toggle*), de larga vida, pensado para que lo opere
  la plataforma.

```text
overlays/<ambiente>/kustomization.yaml
  configMapGenerator circleguard-config
    FEATURE_DENY_SUSPECT_ENTRY=true ──▶ ConfigMap ──▶ Deployment gateway (configMapKeyRef)
                                                           │  variable de entorno
                                                           ▼
                              application.yml: circleguard.features.deny-suspect-entry
                                                           │
                                                           ▼
                                   FeatureToggles ──▶ QrValidationService
```

### 2.1 El toggle `deny-suspect-entry`

| Estado de salud | `FEATURE_DENY_SUSPECT_ENTRY=true` (por defecto) | `FEATURE_DENY_SUSPECT_ENTRY=false` |
|---|---|---|
| `CONFIRMED` (o el valor heredado `CONTAGIED`) | Rechazado (`RED`) | Rechazado (`RED`): no depende del toggle |
| `SUSPECT`, `PROBABLE` (o el heredado `POTENTIAL`) | Rechazado (`RED`), como en la HU-07 | Admitido (`GREEN`) con el mensaje `Welcome to Campus: Health Check Recommended` |
| Sin riesgo, o sin clave en Redis (nunca tuvo un evento de salud) | Admitido (`GREEN`) | Admitido (`GREEN`) |

- El valor por defecto es `true`: si falta la variable, se mantiene la política estricta. Un error de
  configuración nunca deja entrar a nadie que antes se rechazaba.
- Los tres ambientes declaran `true` de forma explícita en su overlay.
- Al arrancar, el gateway registra el valor activo (`Feature toggle deny-suspect-entry=...`) y lo publica
  en `GET /actuator/info` (`{"features": {"deny-suspect-entry": "true"}}`). Así se comprueba que el cambio
  llegó al pod.

### 2.2 Cómo cambiarlo sin una imagen nueva

De forma permanente, se edita la línea del overlay y se despliega como siempre; el pipeline no reconstruye
la imagen del gateway porque no cambió su código. Para un cambio inmediato en un ambiente:

```bash
kubectl -n circleguard-dev patch configmap circleguard-config \
  --type merge -p '{"data":{"FEATURE_DENY_SUSPECT_ENTRY":"false"}}'
kubectl -n circleguard-dev rollout restart deployment/gateway
kubectl -n circleguard-dev rollout status deployment/gateway

# El pod nuevo usa la misma imagen y lee el valor nuevo:
kubectl -n circleguard-dev get deployment gateway -o jsonpath='{.spec.template.spec.containers[0].image}'
curl -s http://<host>/gateway/actuator/info      # {"features":{"deny-suspect-entry":"false"}}
```

Un cambio hecho con `kubectl patch` se pierde en el siguiente despliegue, que vuelve a aplicar el overlay.
Para que quede, hay que cambiarlo también en Git.

## 3. Trade-offs

| A favor | En contra |
|---|---|
| Una sola imagen para los tres ambientes; lo que cambia entre ellos está en el overlay, a la vista y versionado en Git. | Hay que reiniciar los pods para que lean el valor nuevo: las variables de entorno se leen al arrancar. Recargar en caliente necesitaría Spring Cloud Kubernetes o Spring Cloud Config, que es más infraestructura de la que hoy hace falta. |
| El equipo de salud puede relajar o endurecer la regla de acceso en minutos, sin pasar por compilación, imagen y despliegue de código. | El código mantiene los dos caminos, y cada toggle duplica los casos que hay que probar. Las pruebas cubren ambos estados. |
| El valor por defecto es el más seguro, así que una variable faltante no abre el acceso. | Un `kubectl patch` sin el cambio en Git se revierte en el siguiente despliegue. Es intencional (Git manda), pero hay que saberlo. |
| `/actuator/info` y el log muestran el valor activo, lo que facilita auditar qué regla se aplicó. | Un toggle olvidado se vuelve deuda: si la política estricta vuelve a ser la única, conviene retirarlo. |

## 4. Evidencia y pruebas

| Prueba | Qué demuestra |
|---|---|
| `SuspectEntryToggleTest` (gateway, 7 casos) | Arranca la aplicación completa tres veces, cambiando solo la variable `FEATURE_DENY_SUSPECT_ENTRY` (sin definir, `true` y `false`), y llama al endpoint real `POST /api/v1/gate/validate`. Con el mismo código compilado, un usuario `SUSPECT` o `PROBABLE` se rechaza o se admite según la variable; `CONFIRMED` siempre se rechaza; un usuario sano no se ve afectado; `/actuator/info` muestra el valor activo. |
| `QrValidationServiceTest` (3 casos nuevos) | La regla en el servicio con el toggle encendido y apagado, incluidos los valores heredados `POTENTIAL` y `CONTAGIED`. |
| `infra/k8s/validate.py` | En `dev`, `stage` y `prod`, el ConfigMap `circleguard-config` define `FEATURE_DENY_SUSPECT_ENTRY` y el Deployment del gateway lo lee con `configMapKeyRef`. Además, renderiza `dev` con el toggle invertido y comprueba que **solo cambia el ConfigMap**: todos los Deployment, con sus imágenes, quedan idénticos. Esto demuestra que el cambio no genera una imagen nueva. |

```bash
./gradlew :services:circleguard-gateway-service:test --tests '*SuspectEntryToggleTest' --tests '*QrValidationServiceTest'
python infra/k8s/validate.py
```

Las pruebas del gateway no llevan la etiqueta `integration` y corren en la etapa **Test** del pipeline
(Redis se reemplaza con un mock). `validate.py` necesita `kubectl` y se ejecuta de forma local, como el
resto de las validaciones de los manifiestos.

## 5. Archivos

| Archivo | Contenido |
|---|---|
| `services/circleguard-gateway-service/src/main/java/com/circleguard/gateway/config/FeatureToggles.java` | Lee el toggle de la configuración y registra su valor al arrancar. |
| `.../gateway/service/QrValidationService.java` | Aplica la regla de acceso según el toggle. |
| `services/circleguard-gateway-service/src/main/resources/application.yml` | `circleguard.features.deny-suspect-entry: ${FEATURE_DENY_SUSPECT_ENTRY:true}` y su publicación en `/actuator/info`. |
| `infra/k8s/base/kustomization.yaml`, `infra/k8s/overlays/*/kustomization.yaml` | El valor del toggle en el ConfigMap de cada ambiente. |
| `infra/k8s/base/apps/gateway.yaml` | El Deployment lee la variable del ConfigMap. |
| `infra/k8s/validate.py` | Verifica la conexión y que invertir el toggle no cambia ningún Deployment. |
