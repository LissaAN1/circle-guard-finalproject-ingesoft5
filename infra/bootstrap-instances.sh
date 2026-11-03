#!/usr/bin/env bash
# Launches the 6 EC2 servers (idempotent: skips names that already exist).
# Docker is installed at first boot through user-data (install-docker.sh).
# Run bootstrap-keypair.sh and bootstrap-network.sh first.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_aws

AMI="$(aws ssm get-parameter --name "$AMI_SSM_PARAM" --query Parameter.Value --output text)"
log "ami=$AMI"
aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1 \
  || die "key pair $KEY_NAME not found; run bootstrap-keypair.sh"

launch() { # $1 name $2 sg-key
  local name="$1" sgkey="$2" id type disk swap sg
  id="$(instance_id "$name")"
  if [[ -n "$id" ]]; then log "exists  $PROJECT-$name ($id)"; return; fi
  type="$(server_field "$name" 2)"; disk="$(server_field "$name" 3)"; swap="$(server_field "$name" 4)"
  sg="$(sg_id "$sgkey")"; [[ -n "$sg" ]] || die "security group for $sgkey missing; run bootstrap-network.sh"
  local ud; ud="$(mktemp)"
  { echo '#!/usr/bin/env bash'; echo "bash -s $swap <<'EOS'"; cat "$INFRA_DIR/install-docker.sh"; echo 'EOS'; } > "$ud"
  id=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$type" \
    --key-name "$KEY_NAME" --security-group-ids "$sg" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$disk,VolumeType=gp3,DeleteOnTermination=true}" \
    --metadata-options HttpTokens=required,HttpEndpoint=enabled \
    --user-data "file://$ud" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=$PROJECT-$name},{Key=Project,Value=$PROJECT},{Key=Role,Value=$name}]" \
      "ResourceType=volume,Tags=[{Key=Name,Value=$PROJECT-$name},{Key=Project,Value=$PROJECT}]" \
    --query 'Instances[0].InstanceId' --output text)
  rm -f "$ud"
  log "launched $PROJECT-$name ($type, ${disk}GiB) -> $id"
}

for n in "${CICD_SERVERS[@]}"; do launch "$n" cicd; done
for n in "${ENV_SERVERS[@]}";  do launch "$n" "$n"; done
log "waiting for instances to be running..."
ids=$(for n in $(all_server_names); do instance_id "$n"; done | tr '\n' ' ')
# shellcheck disable=SC2086
aws ec2 wait instance-running --instance-ids $ids
log "done. Show addresses with: infra/status.sh"
