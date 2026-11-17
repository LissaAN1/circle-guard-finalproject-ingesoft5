# Manifiestos de Kubernetes (HU-11)

Despliegue de CircleGuard en el clúster k3s de cada ambiente, con [Kustomize](https://kubectl.docs.kubernetes.io/guides/introduction/kustomize/) (viene dentro de `kubectl`, no hay que instalar nada más). Se tomó como base el `compose.base.yaml` de la Parte 1: mismas imágenes, puertos, variables y bases de datos.

```text
infra/k8s/
  base/
    apps/          8 servicios + web (Deployment, Service, probes y límites)
    middleware/    postgres, neo4j, zookeeper, kafka, redis y openldap (StatefulSet con volumen, Service)
    init-db.sql    crea las bases circleguard_* (ConfigMap postgres-init)
  overlays/
    dev|stage|prod/   namespace circleguard-<ambiente>, ConfigMap y réplicas del ambiente
  lib.sh           selección explícita del clúster y lista de workloads (la usan los dos scripts)
  secrets.sh       crea el Secret circleguard-secrets de un ambiente
  deploy.sh        aplica un ambiente con el registro y la versión indicados
  validate.py      verificación sin clúster de los tres ambientes
```

## Namespaces, ConfigMaps y Secrets

| Recurso | Contenido |
|:---|:---|
| Namespace `circleguard-dev`, `-stage`, `-prod` | Aísla cada ambiente (uno por clúster k3s). |
| ConfigMap `circleguard-config` | Configuración no sensible (orígenes CORS). Cambia por ambiente en el overlay. |
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

## Tamaños por ambiente

| | dev | stage | prod |
|:---|:---|:---|:---|
| Réplicas de cada servicio | 1 | 1 | 2 |
| Middleware | 1 réplica con volumen de 1–5 Gi | igual | igual |

## Validación

```bash
python infra/k8s/validate.py
```

Renderiza los tres overlays con `kubectl kustomize` y revisa los scripts. Comprueba: namespace correcto, cada servicio y cada pieza de middleware con su `Service`, puertos, probes de readiness y liveness, límites de recursos, réplicas del ambiente, que los secretos se lean solo de `circleguard-secrets` que no haya un `Secret` ni valores sensibles en claro, que `deploy.sh` espere a cada workload por nombre y que los scripts fijen el clúster y no pasen secretos como argumentos.

**Alcance de esta entrega:** los manifiestos están definidos y validados de forma estática. **No se han aplicado todavía en un clúster k3s real**: la verificación de que los pods quedan `Running` y se comunican (PI-114) se hará al desplegar los ambientes en AWS, junto con la verificación real de HU-10. Quedan por acordar con el equipo: el registro de imágenes (Nexus), y cómo llega Jenkins a la API de cada clúster (ver `infra/terraform/environments/README.md`).
