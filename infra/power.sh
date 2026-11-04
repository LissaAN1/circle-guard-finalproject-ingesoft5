#!/usr/bin/env bash
# Usage: power.sh stop|start [server ...]   (default: all servers)
# Stop suspends compute billing; EBS volumes (and their cost) remain.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_aws
action="${1:-}"; shift || true
[[ "$action" == stop || "$action" == start ]] || die "usage: power.sh stop|start [server ...]"
names=("$@"); [[ ${#names[@]} -gt 0 ]] || mapfile -t names < <(all_server_names)
ids=(); for n in "${names[@]}"; do i="$(instance_id "$n")"; [[ -n "$i" ]] && ids+=("$i"); done
[[ ${#ids[@]} -gt 0 ]] || die "no matching instances"
aws ec2 "${action}-instances" --instance-ids "${ids[@]}" --query 'length(*[0])' --output text >/dev/null
log "$action requested for: ${names[*]}"
[[ "$action" == start ]] && log "public IPs change after start; run infra/status.sh"
exit 0
