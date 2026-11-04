#!/usr/bin/env bash
# Creates the security groups (idempotent). One SG for the CI/CD tools and
# one per environment. Environments never reference each other, so traffic
# between dev/stage/prod is denied by default.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_aws

VPC="$(default_vpc)"; [[ "$VPC" != "None" ]] || die "no default VPC in $AWS_REGION"
IP="$(my_ip)/32"
log "region=$AWS_REGION vpc=$VPC admin_ip=$IP"

ensure_sg() { # $1 key, $2 description
  local id; id="$(sg_id "$1")"
  if [[ -z "$id" ]]; then
    id=$(aws ec2 create-security-group --group-name "$(sg_name "$1")" \
      --description "$2" --vpc-id "$VPC" \
      --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$PROJECT},{Key=Name,Value=$(sg_name "$1")}]" \
      --query GroupId --output text)
    log "created $(sg_name "$1") ($id)"
  else
    log "exists  $(sg_name "$1") ($id)"
  fi
}

ensure_sg cicd  "CircleGuard CI/CD tools (Jenkins, SonarQube, Nexus)"
for e in dev stage prod; do ensure_sg "$e" "CircleGuard $e environment"; done

CICD="$(sg_id cicd)"
# --- CI/CD: admin access only from the operator IP
allow "$CICD" 22   "cidr:$IP" "ssh admin"
allow "$CICD" 8080 "cidr:$IP" "jenkins ui"
allow "$CICD" 9000 "cidr:$IP" "sonarqube ui"
allow "$CICD" 8081 "cidr:$IP" "nexus ui/api"
allow "$CICD" 8082 "cidr:$IP" "nexus docker registry"

for e in dev stage prod; do
  ENV="$(sg_id "$e")"
  # environments pull images from the Nexus registry (one-way: env -> cicd)
  allow "$CICD" 8081 "sg:$ENV" "$e pulls artifacts"
  allow "$CICD" 8082 "sg:$ENV" "$e pulls images"
  # --- environment: ssh from admin and from CI/CD (deployments), web public
  allow "$ENV" 22 "cidr:$IP"  "ssh admin"
  allow "$ENV" 22 "sg:$CICD"  "ssh from jenkins"
  allow "$ENV" 80 "cidr:0.0.0.0/0" "web client"
  for p in 8180 8082 8083 8084 8085 8086 8087 8088; do
    allow "$ENV" "$p" "sg:$CICD" "service $p from cicd (smoke/e2e)"
    allow "$ENV" "$p" "cidr:$IP" "service $p from admin"
  done
done
log "network ready. Verify with: infra/verify.sh"
