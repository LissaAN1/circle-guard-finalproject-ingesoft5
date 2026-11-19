# HU-10 y HU-11: inventario de la infraestructura en AWS (Parte 2)

Estado de los ambientes aplicados con Terraform y desplegados con Kustomize. Este documento no contiene secretos ni direcciones públicas (cambian cada vez que se enciende una instancia). Las IP privadas no cambian.

## Instancias EC2 (12)

| Nombre | Tipo | IP privada | Ambiente | Origen |
|:---|:---|:---|:---|:---|
| `circleguard-jenkins` | c7i-flex.large | 172.31.4.239 | CI/CD | Parte 1 |
| `circleguard-sonarqube` | c7i-flex.large | 172.31.6.46 | CI/CD | Parte 1 |
| `circleguard-nexus` | c7i-flex.large | 172.31.5.84 | CI/CD | Parte 1 |
| `circleguard-dev` | m7i-flex.large | 172.31.17.48 | dev (Compose) | Parte 1 |
| `circleguard-stage` | m7i-flex.large | 172.31.20.20 | stage (Compose) | Parte 1 |
| `circleguard-prod` | m7i-flex.large | 172.31.29.111 | prod (Compose) | Parte 1 |
| `circleguard-dev-server` | m7i-flex.large | 10.0.1.29 | dev (k3s) | Terraform |
| `circleguard-stage-server` | m7i-flex.large | 10.1.1.45 | stage (k3s) | Terraform |
| `circleguard-stage-agent-1` | m7i-flex.large | 10.1.1.198 | stage (k3s) | Terraform |
| `circleguard-prod-server` | m7i-flex.large | 10.2.1.167 | prod (k3s) | Terraform |
| `circleguard-prod-agent-1` | m7i-flex.large | 10.2.1.95 | prod (k3s) | Terraform |
| `circleguard-prod-agent-2` | m7i-flex.large | 10.2.2.245 | prod (k3s) | Terraform |

El límite de la cuenta es de 16 vCPU. Con los 6 nodos k3s encendidos se usan 12; Jenkins y Nexus suman 4 más. SonarQube y los tres ambientes de la Parte 1 deben seguir apagados mientras tanto.

## Redes y conectividad

| Ambiente | VPC | Nodos k3s | Peering con la red de Jenkins y Nexus (172.31.0.0/16) |
|:---|:---|:---|:---|
| dev | 10.0.0.0/16 | 1 servidor | activo |
| stage | 10.1.0.0/16 | 1 servidor + 1 agente | activo |
| prod | 10.2.0.0/16 | 1 servidor + 2 agentes | activo |

- Los nodos k3s descargan las imágenes de Nexus (`172.31.5.84:8082`, HTTP) por el peering. Terraform escribe `/etc/rancher/k3s/registries.yaml` en cada nodo al crearlo; la contraseña de `cg-reader` se lee del parámetro SSM `/circleguard/nexus/cg-reader` (SecureString) y nunca pasa por el repositorio.
- Jenkins llega a la API de k3s (tcp/6443) por IP privada, sin abrir el puerto a Internet. Verificado con Reachability Analyzer en los tres ambientes.
- El certificado de la API cubre la IP privada del servidor y la IP pública que tenía al crearse. **Tras apagar y encender un nodo la IP pública cambia**, así que Jenkins debe usar la IP privada (`10.0.1.29`, `10.1.1.45`, `10.2.1.167`) en su kubeconfig.

## Despliegue verificado

- Imágenes de Nexus con una versión común a las 9: `1.0.0-ci.37.16dffba` (sin `latest`).
- 15 workloads por ambiente (6 StatefulSet y 9 Deployment) listos en dev, stage y prod.
- Ingress de Traefik solo con `/` (web) y `/gateway`.
- 9 HPA por ambiente con métricas reales. Prueba de carga en dev: el gateway escaló de 1 a 2 réplicas y volvió a 1 al terminar.
- Prueba de recuperación: apagar y encender el nodo de dev deja los 16 pods listos sin intervención.

## Hallazgos del despliegue real

Estos fallos no aparecían en las pruebas estáticas y se corrigieron en los PR #61 y #62:

1. La tabla de rutas del módulo `network` borraba en cada `plan` la ruta del peering que agrega `cicd_link`.
2. kafka, neo4j y zookeeper no arrancaban por las variables `<NOMBRE>_PORT` que Kubernetes inyecta (`enableServiceLinks: false`); neo4j además toma toda variable `NEO4J_*` como ajuste.
3. El servicio `file` no podía escribir en su carpeta de subidas.
4. dashboard, file y notification no incluyen Actuator: sus sondas son de puerto TCP hasta que se agregue la dependencia.
5. Con 2 o más réplicas por servicio se agotaban las 100 conexiones de PostgreSQL (ahora 300).
6. Zookeeper y OpenLDAP perdían parte de su estado al reiniciar el nodo (ahora persisten `log` y `slapd.d`).

## Pendientes

- Agregar Actuator a dashboard, file y notification para volver a sondas HTTP.
- Asignar IP elástica o usar siempre la IP privada para el acceso de Jenkins (HU-13).
- Las imágenes de Nexus `ci.37` son anteriores a los PR #57 y #58: hay que construir imágenes nuevas para ver la caché del dashboard y el toggle del gateway en los ambientes.
