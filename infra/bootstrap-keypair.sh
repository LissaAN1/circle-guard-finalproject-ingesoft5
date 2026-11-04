#!/usr/bin/env bash
# Creates the SSH key pair if it does not exist. The private key is written
# to $KEY_DIR (outside the repository) with mode 400 and is never printed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_aws
PEM="$KEY_DIR/$KEY_NAME.pem"
exists=$(aws ec2 describe-key-pairs --key-names "$KEY_NAME" \
  --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || true)
if [[ -n "$exists" && "$exists" != "None" ]]; then
  [[ -f "$PEM" ]] && { log "key pair $KEY_NAME exists and $PEM present"; exit 0; }
  die "key pair $KEY_NAME exists in AWS but $PEM is missing. Use another KEY_NAME or restore the file."
fi
[[ ! -e "$PEM" ]] || die "$PEM already exists locally; refusing to overwrite"
mkdir -p "$KEY_DIR"
umask 077
aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type rsa --key-format pem \
  --tag-specifications "ResourceType=key-pair,Tags=[{Key=Project,Value=$PROJECT}]" \
  --query KeyMaterial --output text > "$PEM"
chmod 400 "$PEM"
log "key pair created; private key saved at $PEM (keep it out of git)"
