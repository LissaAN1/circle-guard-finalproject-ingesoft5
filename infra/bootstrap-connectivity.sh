#!/usr/bin/env bash
# HU-01: authorize CI/CD-to-CI/CD tool communication on the existing TEC-04 SG.
# This is a non-destructive, idempotent addition: no modifications to TEC-04 source.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
require_aws
id="$(sg_id cicd)"
[[ -n "$id" ]] || die 'TEC-04 CI/CD security group not found'
for port in 9000 8081 8082; do
  allow "$id" "$port" "sg:$id" "CI/CD tools internal access"
done
log 'CI/CD security group self-reference added or already present for 9000, 8081, 8082'
