# Seguridad de plataforma: secretos, RBAC y TLS

## Secretos

- Los archivos `infra/environments/.env.dev`, `.env.stage` y `.env.prod` se mantienen fuera de Git y se entregan solo a operadores autorizados. `infra/k8s/secrets.sh` crea o actualiza `circleguard-secrets` usando archivos temporales privados.
- Los archivos `infra/terraform/environments/{dev,stage,prod}/terraform.tfvars`, `backend.hcl`, las llaves SSH y los kubeconfigs también son privados.
- El pipeline ejecuta `Trivy Secrets` inmediatamente después de `Checkout` para ramas y PR. El escaneo es bloqueante. Los detalles del hallazgo se procesan en un archivo temporal eliminado al finalizar; los registros del pipeline solo muestran archivo y regla, nunca el valor detectado.
- Trivy IaC y Trivy Images siguen siendo controles separados y bloqueantes cuando corresponde. El informe JSON del escaneo de secretos **no** se archiva.
- Las contraseñas de ejemplo utilizadas únicamente en `docker-compose.dev.yml` no deben reutilizarse en DEV/STAGE/PROD reales.

## Kubernetes RBAC

| Identidad | Autorización | Restricción |
|---|---|---|
| Administrador K3s | Mantenimiento excepcional de clúster, emisión de tokens y aplicación de TLS | Kubeconfigs privados; nunca usados por Jenkins |
| `jenkins-deployer` | Aplicar manifiestos y actualizar `circleguard-secrets` existente | Sin `pods/exec`, sin `pods/portforward`, sin crear Secret ni Namespace; actualización del Namespace propio |
| `jenkins-e2e` | Obtener Service/Pods, ejecutar fixture de Redis y túnel local para Playwright | Sin permisos para desplegar, leer Secrets ni alterar Namespaces |

`infra/k8s/rbac/provision-kubeconfig.sh` puede emitir dos tipos de token temporal de 24 horas solicitadas (la API puede acortar la duración):

```bash
# El operador usa el contexto administrador privado de cada clúster.
bash infra/k8s/rbac/provision-kubeconfig.sh dev circleguard-dev \
  https://IP_PRIVADA_K3S_DEV:6443 /ruta/segura/kubeconfig-dev deploy
bash infra/k8s/rbac/provision-kubeconfig.sh dev circleguard-dev \
  https://IP_PRIVADA_K3S_DEV:6443 /ruta/segura/kubeconfig-e2e-dev e2e
  