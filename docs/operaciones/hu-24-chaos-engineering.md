# HU-24: Chaos engineering (bonificación de la Parte 2)

Experimentos de caos sobre los servicios de Kubernetes de **dev**, para comprobar que la resiliencia (HU-12, HU-14) y
las alertas (HU-17) responden ante fallas reales. Herramienta: [Chaos Mesh](https://chaos-mesh.org) 2.7.2.

## 1. Instalación y límites

[`infra/chaos/chaos-mesh.yaml`](../../infra/chaos/chaos-mesh.yaml) instala Chaos Mesh con el recurso `HelmChart` que
trae k3s, así que no hace falta helm en el equipo:

```bash
kubectl --context circleguard-dev apply -f infra/chaos/chaos-mesh.yaml
kubectl --context circleguard-dev annotate ns circleguard-dev chaos-mesh.org/inject=enabled
```

- El controlador corre con `enableFilterNamespace`: solo actúa en namespaces con la anotación
  `chaos-mesh.org/inject=enabled`, y solo `circleguard-dev` la tiene. Stage, prod y `kube-system` no pueden recibir
  experimentos.
- Sin dashboard ni servidor DNS, y con límites de CPU y memoria, para no ahogar el nodo de dev (2 vCPU).
- Las pruebas de `ci/tests/test_chaos.py` exigen que cada experimento tenga hipótesis, apunte solo a `circleguard-dev`
  y, si mantiene una falla, tenga duración.

Cada experimento se ejecuta con `infra/chaos/run-experiment.sh`, que siempre lo retira al terminar. Con `ALERT=...`
espera a que esa alerta esté disparada en Alertmanager y falla si no llega.

## 2. Experimento 1: autorrecuperación de un pod

[`01-pod-kill-promotion.yaml`](../../infra/chaos/experiments/01-pod-kill-promotion.yaml)

**Hipótesis.** Con 2 réplicas, matar un pod de `promotion` no deja el servicio caído: el Deployment lo recrea, el
Service sigue atendiendo por la otra réplica y `ServiceDown` no se dispara.

**Resultado (dev, 21 nov 2026, 11:58).** Chaos Mesh mató un pod de promotion. El Service pasó de 2 a 1 endpoint,
siguió atendiendo por el otro pod, y el pod nuevo quedó `Ready` unos 40 s después, con lo que los endpoints volvieron a
2. Hipótesis confirmada. Evidencia: línea de tiempo de pods y endpoints, y eventos `Applied ... pod-kill` de Chaos Mesh.

## 3. Experimento 2: la alerta crítica dispara y se resuelve

[`02-pod-failure-identity.yaml`](../../infra/chaos/experiments/02-pod-failure-identity.yaml)

**Hipótesis.** Si los pods de `identity` dejan de responder 3 minutos, Prometheus ve `up == 0` y la alerta crítica
`ServiceDown` (HU-17) se dispara en menos de 2 minutos; al terminar el experimento los pods se recuperan solos y la
alerta se resuelve.

**Resultado (dev, 21 nov 2026).**

| Hora | Hecho |
|:---|:---|
| 16:56:21 | Se aplica la falla (`pod-failure`, 3 min, modo `all`). La alerta estaba en reposo. |
| 16:56:35 | `up{service="identity"} = 0` |
| 16:57:39 | `ServiceDown{service="identity"}` pasa a **firing** (78 s después; la regla exige 1 min) |
| 16:59:49 | Termina el experimento; el pod vuelve a `Ready`, `up = 1` y la alerta se resuelve |

Hipótesis confirmada: la alerta dispara dentro del plazo y se resuelve sola. Evidencia: consulta `up` de identity en
Prometheus y alerta en Alertmanager.

**Notas de la corrida.**

- Las imágenes que corrían en dev eran anteriores a HU-17 y no exponen `/actuator/prometheus`. Para tener una medición
  real se construyó localmente la imagen de identity del código de `dev` y se importó al nodo
  (`circleguard-identity-service:hu24-chaos`). Es una desviación temporal de dev: el siguiente pipeline de `dev`
  la reemplaza por la imagen del registro.
- El resto de servicios mostraba `ServiceDown` por esa misma razón (sus imágenes no tienen aún el endpoint); no afecta
  al experimento, que filtra por `service="identity"`.
- Tras el experimento el HPA de identity subió a 2 réplicas, como corresponde a su configuración (HU-12).

## 4. Cómo repetirlo

```bash
ENVIRONMENT=dev bash infra/chaos/run-experiment.sh infra/chaos/experiments/01-pod-kill-promotion.yaml
ALERT=ServiceDown ALERT_LABEL=service=identity WAIT_ALERT=270 \
  bash infra/chaos/run-experiment.sh infra/chaos/experiments/02-pod-failure-identity.yaml
```

Requiere el nodo de dev encendido y Prometheus y Alertmanager desplegados (`infra/k8s/observability.sh dev`).
