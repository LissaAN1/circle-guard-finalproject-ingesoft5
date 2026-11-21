# HU-23: Service mesh con mTLS y canary (bonificación de la Parte 2)

Linkerd (edge 2026.11.2) en el clúster de **dev**: proxy inyectado en los servicios, tráfico sin mTLS rechazado y un
despliegue canary que reparte el tráfico entre dos versiones. Linkerd es el mesh más liviano; el nodo de dev tiene
2 vCPU y casi toda su CPU ya estaba reservada por otros pods.

## 1. Instalación

```bash
bash infra/mesh/install.sh        # solo dev
```

- `infra/mesh/issue-certs.sh` emite la raíz de confianza y el emisor de identidad (P-256, 30 días) en
  `infra/mesh/.private/`, que git ignora. La llave del emisor viaja únicamente en un Secret del clúster
  (`linkerd-identity-issuer`), nunca en un manifiesto.
- [`infra/mesh/linkerd.yaml`](../../infra/mesh/linkerd.yaml) instala `linkerd-crds` y `linkerd-control-plane` con el
  recurso `HelmChart` de k3s (sin helm en el equipo). Las solicitudes de CPU y memoria son mínimas
  (5 m por componente, 2 m por proxy): el plano de control completo suma unos 21 m de CPU reservada.
- Las rutas canary usan el `HTTPRoute` propio de Linkerd (`policy.linkerd.io/v1beta3`), porque el clúster no tiene las
  CRD de Gateway API.

## 2. Criterio 1: los servicios tienen el proxy inyectado

El parche del overlay de dev ([`infra/k8s/overlays/dev/kustomization.yaml`](../../infra/k8s/overlays/dev/kustomization.yaml))
anota con `linkerd.io/inject: enabled` todos los Deployment de dev. Stage y prod no cambian, y las bases de datos y
brokers (StatefulSet) quedan fuera de la malla. Si Linkerd no está instalado, la anotación se ignora.

Resultado en dev: los 9 servicios (auth, dashboard, file, form, gateway, identity, notification, promotion y web)
corren con el contenedor `linkerd-proxy` (`READY 2/2`). El acceso externo por Traefik (que no está en la malla) sigue
respondiendo (HTTP 200) y Prometheus, que tampoco está en la malla, sigue raspando a identity ya con su proxy.

## 3. Criterio 2: el tráfico sin mTLS se rechaza

[`infra/mesh/demo/mesh-demo.yaml`](../../infra/mesh/demo/mesh-demo.yaml) crea el namespace `mesh-demo` con
`config.linkerd.io/default-inbound-policy: all-authenticated`: solo acepta clientes con identidad de la malla.

`bash infra/mesh/verify.sh` lanza dos clientes contra `hello-v1`:

| Cliente | Resultado |
|:---|:---|
| con proxy (identidad de la malla, mTLS) | responde `hello from v1` |
| sin proxy (`linkerd.io/inject: disabled`) | **rechazado por el proxy, HTTP 403** |

## 4. Criterio 3: canary entre dos versiones

El Service `hello` tiene un `HTTPRoute` que envía el 90 % de las peticiones a `hello-v1` y el 10 % a `hello-v2`.
Con 100 peticiones el reparto medido fue 92 / 8 (y 93 / 7 en una corrida anterior), dentro de lo esperado.

## 5. Alcance y límites

- La política estricta se demuestra en `mesh-demo`. En `circleguard-dev` los servicios están en la malla pero con la
  política por defecto (permisiva): Traefik y Prometheus no están en la malla y quedarían rechazados con
  `all-authenticated`. Extender la política estricta a los servicios reales requiere meter primero esos dos en la malla.
- El canary se demuestra con dos versiones de un servicio de prueba (`hashicorp/http-echo`), no con dos imágenes reales
  de CircleGuard, para que el reparto sea visible.
- Los certificados duran 30 días; es una malla de evaluación, no de producción.
- Pruebas sin clúster: `python -m pytest ci/tests/test_mesh.py` (llaves ignoradas por git, política estricta, canary que
  suma 100, emisor en Secret e inyección solo en dev).
