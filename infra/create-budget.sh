#!/usr/bin/env bash
# Creates a monthly cost budget with e-mail alerts at 50/80/100% (idempotent).
# Usage: create-budget.sh <email> [monthly_usd=50]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_aws
EMAIL="${1:-}"; LIMIT="${2:-50}"
[[ "$EMAIL" == *@* ]] || die "usage: create-budget.sh <email> [monthly_usd]"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
NAME="$PROJECT-monthly"
if aws budgets describe-budget --account-id "$ACCOUNT" --budget-name "$NAME" >/dev/null 2>&1; then
  log "budget $NAME already exists"; exit 0
fi
notif() { printf '{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":%s,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"%s"}]}' "$1" "$EMAIL"; }
aws budgets create-budget --account-id "$ACCOUNT" \
  --budget "{\"BudgetName\":\"$NAME\",\"BudgetLimit\":{\"Amount\":\"$LIMIT\",\"Unit\":\"USD\"},\"TimeUnit\":\"MONTHLY\",\"BudgetType\":\"COST\"}" \
  --notifications-with-subscribers "$(notif 50)" "$(notif 80)" "$(notif 100)"
log "budget $NAME created ($LIMIT USD/month, alerts to $EMAIL)"
