# Registro de cambios en ambientes

Cambios aplicados a mano en los clústeres, fuera del pipeline, y cómo revertirlos (HU-22). Los cambios que despliega el
pipeline quedan en el historial de Jenkins y en `CHANGELOG.md`; aquí solo se anota lo que no pasa por ahí.

| Fecha | Ambiente | Cambio | Responsable | Cómo se revierte |
|:---|:---|:---|:---|:---|
| 2026-11-21 | dev | Instalación de Chaos Mesh 2.7.2 y anotación `chaos-mesh.org/inject=enabled` en `circleguard-dev` (HU-24) | Daniel Trujillo | `kubectl delete -f infra/chaos/chaos-mesh.yaml` y quitar la anotación del namespace |
| 2026-11-21 | dev | Imagen de `identity` cambiada a `circleguard-identity-service:hu24-chaos` (local, con `/actuator/prometheus`) para medir la alerta ServiceDown | Daniel Trujillo | `bash infra/k8s/rollback.sh dev identity`, o el siguiente pipeline de `dev` la reemplaza |
| 2026-11-21 | dev | Instalación de Linkerd y proxy inyectado en los 9 Deployment (HU-23) | Daniel Trujillo | quitar la anotación `linkerd.io/inject` del overlay y redesplegar; `kubectl delete -f infra/mesh/linkerd.yaml` |
| 2026-11-21 | dev | Namespace `mesh-demo` con la demostración de canary | Daniel Trujillo | `kubectl delete -f infra/mesh/demo/mesh-demo.yaml` |
