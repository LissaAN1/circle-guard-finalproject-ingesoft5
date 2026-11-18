# Manifiestos de Kubernetes (HU-11)

Despliegue de CircleGuard en el clúster k3s de cada ambiente, con [Kustomize](https://kubectl.docs.kubernetes.io/guides/introduction/kustomize/) (viene dentro de `kubectl`, no hay que instalar nada más). Se tomó como base el `compose.base.yaml` de la Parte 1: mismas imágenes, puertos, variables y bases de datos.

```text
infra/k8s/
  base/
    apps/          8 servicios + web (Deployment, Service, probes y límites)
    hpa/           un HorizontalPodAutoscaler por servicio y para web (HU-12)
    ingress.yaml   Ingress de Traefik para web y gateway, y su Middleware (HU-12)
    middleware/    postgres, neo4j, zookeeper, kafka, redis y openldap (StatefulSet con volumen, Service)
    init-db.sql    crea las bases circleguard_* (ConfigMap postgres-init)
  overlays/
    dev|stage|prod/   namespace circleguard-<ambiente>, ConfigMap, límites del HPA y Middleware del ambiente
  lib.sh           selección explícita del clúster y lista de workloads (la usan los dos scripts)
  secrets.sh       crea el Secret circleguard-secrets de un ambiente
  deploy.sh        aplica un ambiente con el registro y la versión indicados
  validate.py      verificación sin clúster de los tres ambientes
```

## Namespaces, ConfigMaps y Secrets

| Recurso | Contenido |
|:---|:---|
| Namespace `circleguard-dev`, `-stage`, `-prod` | Aísla cada ambiente (uno por clúster k3s). |
| ConfigMap `circleguard-config` | Configuración no sensible (orígenes CORS) y feature toggles (`FEATURE_DENY_SUSPECT_ENTRY`, HU-15). Cambia por ambiente en el overlay. |
| ConfigMap `postgres-init` | `init-db.sql`: crea `circleguard_auth`, `identity`, `promotion`, `dashboard` y `form`. |
| Secret `circleguard-secrets` | `DB_USER`, `DB_PASSWORD`, `NEO4J_PASSWORD`, `LDAP_ADMIN_PASSWORD`, `REDIS_PASSWORD`, `JWT_SECRET`, `QR_SECRET`, `VAULT_SECRET`, `VAULT_SALT`, `VAULT_HASH_SALT`. **No está en el repositorio**: lo crea `secrets.sh` a partir de `infra/environments/.env.<ambiente>` (que genera `create-env.sh` y git ignora). |

Los pods leen los secretos con `secretKeyRef`; ningún valor sensible aparece en los manifiestos (`validate.py` lo comprueba).

## Comunicación entre servicios

Cada servicio tiene un `Service` con el mismo nombre que usaba Compose (`postgres`, `kafka`, `redis`, `auth`, `identity`...), así que las URLs de las variables de entorno no cambian y el `nginx` de `web` encuentra `auth`, `identity`, `promotion`, `form` y `gateway`. Dentro del namespace se resuelven por nombre corto.

| Origen | Destino |
|:---|:---|
| auth, identity, promotion, form, dashboard | `postgres:5432` (una base por servicio) |
| auth | `openldap:389`, `identity:8083` |
| promotion | `neo4j:7687`, `kafka:9092`, `redis:6379` |
| form, notification | `kafka:9092` |
| gateway, promotion | `redis:6379` |
| dashboard | `promotion:8088` |
| notification | `auth:8180` |
| web | `auth`, `identity`, `promotion`, `form`, `gateway` |
| kafka | `zookeeper:2181` |

## Uso

```bash
bash infra/environments/create-env.sh dev      # genera los secretos privados (una vez)
bash infra/k8s/secrets.sh dev                  # crea circleguard-secrets en circleguard-dev
bash infra/k8s/deploy.sh dev <registro> <versión>
kubectl -n circleguard-dev get pods
```

`deploy.sh` aplica el overlay y espera, uno por uno y por nombre, a los 6 StatefulSet y los 9 Deployment (`kubectl rollout status statefulset/<nombre>` y `deployment/<nombre>`). Si alguno no queda listo en 10 minutos el script termina con código distinto de cero, de modo que un pipeline pueda detener la promoción. La lista de workloads está en `lib.sh` y `validate.py` comprueba que coincida con lo que renderizan los manifiestos.

### Clúster de destino

Los scripts nunca usan el contexto actual de `kubectl`. Actúan sobre `KUBE_CONTEXT` (por defecto `circleguard-<ambiente>`) y se niegan a continuar si ese contexto no existe, si su nombre no corresponde al ambiente pedido o si corresponde a otro ambiente (por ejemplo, `circleguard-dev` al desplegar `prod`). Cada comando `kubectl` lleva `--context` explícito. Para otro nombre de contexto: `KUBECONFIG=/ruta/kubeconfig-prod KUBE_CONTEXT=mi-clúster-prod bash infra/k8s/deploy.sh prod ...`; el nombre debe contener el ambiente (`prod`) como palabra.

### Secretos

`secrets.sh` no pasa los valores como argumentos (se verían en la lista de procesos): escribe cada uno en un archivo con permisos `0600` dentro de un directorio temporal privado (`0700`, en `$XDG_RUNTIME_DIR` si existe), crea el Secret con `--from-file` y borra el directorio al terminar, también si falla. No imprime valores, así que es seguro en los registros de Jenkins.

## Exposición y autoescalado (HU-12)

**Ingress.** k3s trae Traefik como controlador de Ingress, así que no se instala nada. Hay dos Ingress de clase `traefik` en el puerto 80 del servidor k3s (el security group de `network` ya lo abre):

| Ruta | Destino | Nota |
|:---|:---|:---|
| `/` | `web:80` | Cliente web. |
| `/gateway` | `gateway:8087` | Un `Middleware` de Traefik (`strip-gateway`) quita el prefijo `/gateway` antes de llegar al servicio. Su anotación lleva el namespace del ambiente (`circleguard-<ambiente>-strip-gateway@kubernetescrd`), que cada overlay fija. |

Sin dominio, se accede por la IP pública del servidor (`server_public_ip` de Terraform): `http://<ip>/` y `http://<ip>/gateway/actuator/health`. Los Ingress no tienen `host`; si más adelante hay DNS, se agrega por overlay. No hay TLS en este avance.

**HPA.** Cada uno de los 8 servicios y `web` tiene un `HorizontalPodAutoscaler` (`autoscaling/v2`) por CPU, con objetivo del 70 % de la solicitud de CPU (`requests.cpu` de cada Deployment). Los Deployment ya no fijan `replicas`: el HPA manda, y así un nuevo `apply` no lo pisa. Sube sin espera (hasta 2 pods cada 30 s) y baja tras 180 s de calma. Requiere metrics-server, que k3s incluye.

| | dev | stage | prod |
|:---|:---|:---|:---|
| Réplicas mínimas por servicio | 1 | 1 | 2 |
| Réplicas máximas por servicio | 2 | 3 | 5 |

El middleware (postgres, neo4j, zookeeper, kafka, redis y openldap) no escala: 1 réplica con volumen de 1 a 5 Gi en todos los ambientes.

**Sondas.** Los 8 servicios usan el endpoint de Actuator `/actuator/health` en las tres sondas: `startupProbe` (hasta 5 minutos para arrancar, sin penalizar el arranque lento de Spring), `readinessProbe` (saca el pod del Service si deja de responder) y `livenessProbe` (reinicia el contenedor tras 5 fallos seguidos). `web` (nginx) no tiene Actuator y usa `/`.

## Validación

```bash
python infra/k8s/validate.py
```

Renderiza los tres overlays con `kubectl kustomize` y revisa los scripts. Comprueba: namespace correcto, cada servicio y cada pieza de middleware con su `Service`, puertos, las tres sondas (en Actuator para los servicios), límites y solicitud de CPU, un HPA por CPU por servicio con los límites del ambiente y sin `replicas` fijas, los Ingress de `/` (web) y `/gateway` con su Middleware, que los secretos se lean solo de `circleguard-secrets` que no haya un `Secret` ni valores sensibles en claro, que `deploy.sh` espere a cada workload por nombre y que los scripts fijen el clúster y no pasen secretos como argumentos.

**Alcance de esta entrega:** los manifiestos están definidos y validados de forma estática; el comportamiento real del Ingress y del escalado (PI-117) se comprueba en un k3s desplegado, abajo se indica cómo. **No se han aplicado todavía en un clúster k3s real**: la verificación de que los pods quedan `Running` y se comunican (PI-114) se hará al desplegar los ambientes en AWS, junto con la verificación real de HU-10. Quedan por acordar con el equipo: el registro de imágenes (Nexus), y cómo llega Jenkins a la API de cada clúster (ver `infra/terraform/environments/README.md`).

## Verificar el escalado en un clúster (PI-117)

Con el ambiente desplegado y `KUBE_CONTEXT` apuntando a él:

```bash
kubectl --context circleguard-dev -n circleguard-dev get hpa                     # TARGETS debe mostrar un % de CPU, no <unknown>
curl -s http://<server_public_ip>/gateway/actuator/health                         # {"status":"UP"} a través del Ingress
kubectl --context circleguard-dev -n circleguard-dev run carga --rm -it --image=busybox:1.36 --restart=Never --   sh -c 'while true; do wget -q -O- http://gateway:8087/actuator/health >/dev/null; done'   # genera carga
kubectl --context circleguard-dev -n circleguard-dev get hpa gateway -w          # las réplicas suben y, al parar la carga, bajan tras ~3 min
```

Esta verificación requiere el despliegue real en AWS y queda pendiente igual que PI-114.
