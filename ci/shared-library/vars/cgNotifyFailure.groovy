// Sends a failure/unstable build notice to the configured Slack-compatible webhook.
// The webhook URL is passed through a private curl configuration file, never argv.
def call() {
    if (!env.NOTIFY_WEBHOOK_URL?.trim()) {
        echo 'Failure notification unavailable: configure NOTIFY_WEBHOOK_URL in Jenkins.'
        return
    }
    String message = "CircleGuard: ${env.JOB_NAME ?: 'pipeline'} #${env.BUILD_NUMBER ?: '?'} " +
        "${currentBuild.currentResult}; ${env.BUILD_URL ?: 'see Jenkins'}"
    try {
        writeFile file: 'hu13-notification.json',
            text: groovy.json.JsonOutput.toJson([text: message])
        sh(label: 'notify-failure', script: '''#!/usr/bin/env bash
set -euo pipefail
umask 077
cfg="$(mktemp)"
trap 'rm -f "$cfg" hu13-notification.json' EXIT
[[ "$NOTIFY_WEBHOOK_URL" == https://* ]] || { echo 'Webhook must use HTTPS' >&2; exit 1; }
printf 'url = "%s"\n' "$NOTIFY_WEBHOOK_URL" > "$cfg"
curl --fail --silent --show-error --max-time 15 \
  --config "$cfg" -H 'Content-Type: application/json' \
  -X POST --data-binary '@hu13-notification.json' >/dev/null
''')
    } catch (Exception ex) {
        echo "Failure webhook could not be delivered: ${ex.getClass().getSimpleName()}"
    }
}
