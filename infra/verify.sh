#!/usr/bin/env bash
# Checks the TEC-04 acceptance criteria against the live account.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_aws
fail=0; ok(){ log "OK   $*"; }; bad(){ log "FAIL $*"; fail=1; }

# 1. all six servers exist
for n in $(all_server_names); do
  [[ -n "$(instance_id "$n")" ]] && ok "server $PROJECT-$n" || bad "server $PROJECT-$n missing"
done

# 2. no env SG references another env SG, so inter-environment traffic is denied
for e in dev stage prod; do
  id="$(sg_id "$e")"; [[ -n "$id" ]] || { bad "sg $e missing"; continue; }
  refs=$(aws ec2 describe-security-groups --group-ids "$id" \
    --query 'SecurityGroups[0].IpPermissions[].UserIdGroupPairs[].GroupId' --output text)
  bad_ref=0
  for o in dev stage prod; do
    [[ "$o" == "$e" ]] && continue
    oid="$(sg_id "$o")"; [[ " $refs " == *" $oid "* ]] && bad_ref=1
  done
  (( bad_ref )) && bad "$e allows traffic from another environment" || ok "$e isolated from other environments"
done

# 3. SSH never open to the world
for k in cicd dev stage prod; do
  id="$(sg_id "$k")"; [[ -n "$id" ]] || continue
  open=$(aws ec2 describe-security-groups --group-ids "$id" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[?CidrIp==`0.0.0.0/0`]|[]' --output text)
  [[ -z "$open" ]] && ok "ssh not public on $k" || bad "ssh open to 0.0.0.0/0 on $k"
done

# 4. no key material tracked in git
if git -C "$INFRA_DIR/.." ls-files | grep -Ei '\.(pem|ppk)$|^infra/\.env$' >/dev/null; then
  bad "key material tracked in git"; else ok "no keys tracked in git"; fi
exit $fail
