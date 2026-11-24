#!/usr/bin/env bash
# Make sure the two dedicated E2E accounts exist in the DEV auth database.
#
# CircleGuard logs in against LDAP first and falls back to the local database. DEV LDAP has no
# entries, so every DEV login is resolved by circleguard_auth.local_users. Flyway only seeds
# staff_guard, health_user and super_admin, therefore the dedicated accounts are created here,
# with the passwords stored in the Jenkins credentials. The step is idempotent: it can run on
# every build and recreates the accounts if the environment was initialised again.
#
# - Only the two accounts named by E2E_USERNAME and E2E_GATE_USERNAME are touched.
# - The seeded users are rejected by name, so their credentials are never modified.
# - Passwords travel on stdin of `kubectl exec`; they are never placed in an argument or printed.
# - The hash is computed by PostgreSQL (pgcrypto bcrypt, compatible with Spring's BCryptPasswordEncoder).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
env_name="${1:-}"
[[ "$env_name" == dev ]] || { echo 'Usage: ensure-e2e-users.sh dev (stage accounts are managed separately)' >&2; exit 2; }
: "${E2E_USERNAME:?E2E survey account is required}"
: "${E2E_PASSWORD:?E2E survey password is required}"
: "${E2E_GATE_USERNAME:?E2E gate account is required}"
: "${E2E_GATE_PASSWORD:?E2E gate password is required}"

survey_user="$E2E_USERNAME"; gate_user="$E2E_GATE_USERNAME"
for account in "$survey_user" "$gate_user"; do
  [[ "$account" =~ ^[a-z0-9_]{3,64}$ ]] || { echo 'E2E account names must be 3-64 chars of [a-z0-9_]' >&2; exit 2; }
  case "$account" in
    staff_guard|health_user|super_admin) echo 'Refusing to manage a seeded user as an E2E account' >&2; exit 2 ;;
  esac
done
[[ "$survey_user" != "$gate_user" ]] || { echo 'Survey and gate E2E accounts must be different' >&2; exit 2; }

# psql \set takes a quoted string: escape backslashes and single quotes, refuse line breaks.
psql_quote() {
  local value="$1"
  [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || { echo 'Invalid E2E password' >&2; exit 2; }
  value="${value//\\/\\\\}"
  printf "'%s'" "${value//\'/\\\'}"
}

cd "$ROOT"
source infra/k8s/lib.sh
KUBE_CONTEXT="${KUBE_CONTEXT:-circleguard-$env_name}"
select_cluster "$env_name"
ns="circleguard-$env_name"

emit_sql() {
  printf '%s\n' '\set ON_ERROR_STOP on'
  printf '\\set su %s\n' "'$survey_user'"
  printf '\\set gu %s\n' "'$gate_user'"
  printf '\\set sp %s\n' "$(psql_quote "$E2E_PASSWORD")"
  printf '\\set gp %s\n' "$(psql_quote "$E2E_GATE_PASSWORD")"
  cat <<'EOF_SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- One statement per account. An existing row is only rewritten when Jenkins holds a different
-- password (rotation) or the account was disabled; otherwise nothing changes.
INSERT INTO local_users (username, password_hash, email, is_active)
VALUES (:'su', crypt(:'sp', gen_salt('bf', 10)), :'su' || '@e2e.circleguard.test', true)
ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, is_active = true
  WHERE local_users.password_hash <> crypt(:'sp', local_users.password_hash) OR NOT local_users.is_active;
INSERT INTO local_users (username, password_hash, email, is_active)
VALUES (:'gu', crypt(:'gp', gen_salt('bf', 10)), :'gu' || '@e2e.circleguard.test', true)
ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, is_active = true
  WHERE local_users.password_hash <> crypt(:'gp', local_users.password_hash) OR NOT local_users.is_active;
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM local_users u JOIN roles r
  ON (u.username = :'su' AND r.name = 'STUDENT') OR (u.username = :'gu' AND r.name = 'GATE_STAFF')
ON CONFLICT (user_id, role_id) DO NOTHING;
-- Verification, one number per line: accounts that are active with the expected role (2),
-- and gate:scan reachable from the gate account (1).
SELECT count(*) FROM local_users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id
 WHERE u.is_active
   AND ((u.username = :'su' AND r.name = 'STUDENT') OR (u.username = :'gu' AND r.name = 'GATE_STAFF'));
SELECT count(*) FROM local_users u JOIN user_roles ur ON ur.user_id = u.id
  JOIN role_permissions rp ON rp.role_id = ur.role_id JOIN permissions p ON p.id = rp.permission_id
 WHERE u.username = :'gu' AND p.name = 'gate:scan';
EOF_SQL
}

# The Role of jenkins-e2e allows pods/exec; the database password comes from the pod's own environment.
result="$(emit_sql | kc -n "$ns" exec -i statefulset/postgres -- sh -c \
  'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -X -q -At -U "$POSTGRES_USER" -d circleguard_auth')"
checks="$(printf '%s\n' "$result" | tail -n 2 | tr '\n' ' ')"
[[ "$checks" == "2 1 " ]] || { echo 'E2E account verification failed (expected 2 role assignments and gate:scan)' >&2; exit 1; }
echo "E2E accounts ensured in $ns (survey: STUDENT, gate: GATE_STAFF with gate:scan)"
