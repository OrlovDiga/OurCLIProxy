#!/bin/sh
set -eu

: "${MGMT_SECRET:?MGMT_SECRET env var is required}"
: "${API_KEYS:?API_KEYS env var is required (comma-separated)}"

cat > /CLIProxyAPI/config.yaml <<EOF
port: ${PORT:-8317}
auth-dir: /root/.cli-proxy-api
debug: false
logging-to-file: false

remote-management:
  allow-remote: true
  secret-key: "${MGMT_SECRET}"

api-keys:
$(printf '%s' "${API_KEYS}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^/  - "/;s/$/"/')

request-retry: 3
quota-exceeded:
  switch-project: true
  switch-preview-model: true
EOF

cd /CLIProxyAPI
exec ./CLIProxyAPI
