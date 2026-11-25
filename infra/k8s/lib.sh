# Shared helpers of secrets.sh and deploy.sh (sourced, not executed).
# Every kubectl call goes through `kc`, which pins the cluster explicitly.

WORKLOAD_STATEFULSETS=(postgres neo4j zookeeper kafka redis openldap)
WORKLOAD_DEPLOYMENTS=(auth identity promotion form gateway dashboard file notification web)

# select_cluster <env>
# The cluster is never the "current" kubectl context. It is KUBE_CONTEXT, or
# circleguard-<env> by default, and its name must belong to <env>: a context named
# for another environment (dev/stage/prod) or for none is rejected, so a wrong
# kubeconfig cannot receive the deploy or the secrets of this environment.
select_cluster() {
  local env="$1" other
  KUBE_CONTEXT="${KUBE_CONTEXT:-circleguard-$env}"
  if ! kubectl config get-contexts -o name | grep -qxF -- "$KUBE_CONTEXT"; then
    echo "kubectl context '$KUBE_CONTEXT' does not exist. Set KUBE_CONTEXT (and KUBECONFIG) to the $env cluster." >&2
    return 1
  fi
  if [[ ! "$KUBE_CONTEXT" =~ (^|[-_./])${env}($|[-_./]) ]]; then
    echo "kubectl context '$KUBE_CONTEXT' is not named for the '$env' environment; refusing to continue." >&2
    return 1
  fi
  for other in dev stage prod; do
    if [[ "$other" != "$env" && "$KUBE_CONTEXT" =~ (^|[-_./])${other}($|[-_./]) ]]; then
      echo "kubectl context '$KUBE_CONTEXT' belongs to '$other', not '$env'; refusing to continue." >&2
      return 1
    fi
  done
  echo "Cluster: context '$KUBE_CONTEXT' for environment '$env'"
}

kc() { kubectl --context "$KUBE_CONTEXT" "$@"; }
