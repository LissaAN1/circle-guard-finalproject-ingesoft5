#!/usr/bin/env bash
# CircleGuard HU-07: backwards-compatible DEV E2E entrypoint.
# Uses the existing authorized DEV credentials and shared E2E runner.
set -euo pipefail

: "${E2E_DEV_HOST:?Authorized DEV EC2 hostname/IP is required}"

export E2E_TARGET_HOST="$E2E_DEV_HOST"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "$SCRIPT_DIR/run-env.sh" dev
