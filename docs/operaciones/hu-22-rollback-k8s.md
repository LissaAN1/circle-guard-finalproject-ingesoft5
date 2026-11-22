# Plan de Rollback en Kubernetes (HU-22)

Procedimiento estándar para revertir despliegues en los clústeres k3s de CircleGuard (`dev`, `stage` y `prod`) manteniendo trazabilidad en el registro de cambios.

## 1. Criterios de activación

Se ejecuta un rollback cuando, tras un despliegue en cualquier ambiente, ocurre alguno de los siguientes eventos:

- Las sondas de salud (`startupProbe`, `readinessProbe` o `livenessProbe`) fallan y el rollout no completa en el tiempo límite.
- Se disparan alertas críticas en Prometheus (`ServiceDown`, `HighErrorRate` o `CircuitBreakerOpen`, HU-17).
- Fallan las pruebas E2E post-despliegue (Playwright) o se detecta una regresión funcional crítica.

## 2. Estrategias de rollback

### A. Rollback rápido de un servicio puntual (recomendado ante fallas aisladas)

Usa `infra/k8s/rollback.sh`, que fija explícitamente el contexto del clúster (`select_cluster`) para evitar operar sobre el ambiente equivocado:

```bash
# Revertir a la revisión inmediatamente anterior
KUBE_CONTEXT=circleguard-dev bash infra/k8s/rollback.sh dev auth

# Revertir a una revisión específica del historial
KUBE_CONTEXT=circleguard-dev bash infra/k8s/rollback.sh dev auth 2
```

### B. Varios servicios o todo el ambiente

El script revierte un Deployment por ejecución. Si la falla afecta a varios servicios, se repite el comando por cada
uno (el orden no importa; cada `rollout undo` espera a que el servicio quede sano):

```bash
for s in auth gateway identity; do
  KUBE_CONTEXT=circleguard-dev bash infra/k8s/rollback.sh dev "$s"
done
```

Si lo que falló fue el despliegue completo, la alternativa es volver a desplegar la versión anterior con el pipeline
de Jenkins (`APP_VERSION` anterior), como hace `ci/deploy/deploy-remote.sh` ante una falla.

## 3. Verificación tras el rollback

- `rollout status` del script termina sin error y los pods del servicio quedan `Ready`.
- En Prometheus, la alerta que motivó el rollback se resuelve (HU-17).
- Las pruebas E2E del ambiente vuelven a pasar.

## 4. Trazabilidad

Cada rollback y cada cambio manual en un ambiente se anota en
[`registro-cambios-ambientes.md`](registro-cambios-ambientes.md): fecha, ambiente, qué cambió, quién y cómo se revierte.

## 5. Límites

- `rollout undo` solo conoce las revisiones que guarda el Deployment (por defecto, las últimas 10).
- Un rollback devuelve la imagen y la configuración del Deployment, no los datos de las bases.
- Prod exige el mismo contexto de clúster que el ambiente indicado; el script se niega si no coincide.
