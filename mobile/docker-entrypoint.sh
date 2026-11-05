#!/bin/sh
# Genera /config.js con las URLs de los servicios a partir de variables de entorno.
set -eu
cat > /usr/share/nginx/html/config.js <<JS
window.__CG_CONFIG__ = {
  AUTH_BASE_URL: "${AUTH_BASE_URL:-http://localhost:8180}",
  DASHBOARD_BASE_URL: "${DASHBOARD_BASE_URL:-http://localhost:8084}",
  FILE_BASE_URL: "${FILE_BASE_URL:-http://localhost:8085}",
  FORM_BASE_URL: "${FORM_BASE_URL:-http://localhost:8086}",
  GATEWAY_BASE_URL: "${GATEWAY_BASE_URL:-http://localhost:8087}",
  IDENTITY_BASE_URL: "${IDENTITY_BASE_URL:-http://localhost:8083}",
  NOTIFICATION_BASE_URL: "${NOTIFICATION_BASE_URL:-http://localhost:8082}",
  PROMOTION_BASE_URL: "${PROMOTION_BASE_URL:-http://localhost:8088}"
};
JS
exec nginx -g 'daemon off;'