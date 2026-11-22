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
