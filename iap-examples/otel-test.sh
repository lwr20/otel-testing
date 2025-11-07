#!/bin/bash
# Send OTEL trace using otel-cli with IAP authentication
# Based on https://docs.cloud.google.com/iap/docs/authentication-howto

set -e

# --- Check for required commands ---
if ! command -v otel-cli &>/dev/null; then
  echo "otel-cli is required. Install from: https://github.com/equinix-labs/otel-cli/releases" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "jq is required. Please install jq." >&2
  exit 1
fi

if ! command -v gcloud &>/dev/null; then
  echo "gcloud is required. Please install the Google Cloud SDK." >&2
  exit 1
fi

# --- CONFIGURATION ---
export SERVICE_ACCOUNT_KEY="/home/lance/Downloads/tigera-dev-tools-24b915217988.json"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://banzai-otel.dev-tools.tigera.net"

SERVICE_ACCOUNT_EMAIL_ADDRESS=$(jq -r .client_email "$SERVICE_ACCOUNT_KEY")
IAT=$(date +%s)
EXP=$((IAT + 3600))

# --- JWT signing using gcloud ---
sign_jwt_gcloud() {
  cat > /tmp/claim.json << EOM
{
  "iss": "$SERVICE_ACCOUNT_EMAIL_ADDRESS",
  "sub": "$SERVICE_ACCOUNT_EMAIL_ADDRESS",
  "aud": "$OTEL_EXPORTER_OTLP_ENDPOINT/*",
  "iat": $IAT,
  "exp": $EXP
}
EOM
  gcloud iam service-accounts sign-jwt --iam-account="$SERVICE_ACCOUNT_EMAIL_ADDRESS" /tmp/claim.json /tmp/output.jwt
  local jwt
  jwt=$(cat /tmp/output.jwt)
  if [[ -z "$jwt" || "$jwt" == "null" ]]; then
    echo "Failed to generate IAP JWT with gcloud." >&2
    return 1
  fi
  echo "$jwt"
}

# --- JWT signing using openssl (RS256) ---
# Requires: openssl, jq, base64, and the private key extracted from the service account JSON
sign_jwt_openssl() {
  local header='{"alg":"RS256","typ":"JWT"}'
  local payload
  payload=$(cat <<EOP
{
  "iss": "$SERVICE_ACCOUNT_EMAIL_ADDRESS",
  "sub": "$SERVICE_ACCOUNT_EMAIL_ADDRESS",
  "aud": "$OTEL_EXPORTER_OTLP_ENDPOINT/*",
  "iat": $IAT,
  "exp": $EXP
}
EOP
  )
  # base64url encode header and payload
  local header_b64
  header_b64=$(echo -n "$header" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  local payload_b64
  payload_b64=$(echo -n "$payload" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  local signing_input="$header_b64.$payload_b64"
  # Extract private key from service account JSON
  local privkey_file="/tmp/sa.key"
  jq -r .private_key "$SERVICE_ACCOUNT_KEY" > "$privkey_file"
  # Sign with openssl (RS256)
  local signature
  signature=$(echo -n "$signing_input" | openssl dgst -sha256 -sign "$privkey_file" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  local jwt
  jwt="$signing_input.$signature"
  # Clean up
  rm -f "$privkey_file"
  echo "$jwt"
}

# --- Choose signing method ---
# if command -v gcloud &>/dev/null; then
#   IAP_JWT=$(sign_jwt_gcloud)
# else
  IAP_JWT=$(sign_jwt_openssl)
# fi

if [[ -z "$IAP_JWT" || "$IAP_JWT" == "null" ]]; then
  echo "Failed to generate IAP JWT."
  exit 1
fi

echo "✓ Generated IAP JWT"

send_trace_with_cli() {
  local jwt="$1"               # JWT to use for Authorization header
  local service_name="${2:-otel-cli-test-service}"  # OTEL service name
  local attrs="${3:-test.attribute=example-value,environment=dev}" # Span attributes

  # --- Send trace using otel-cli ---
  # otel-cli uses environment variables for configuration
  export OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"  # Use HTTP with protobuf
  export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer ${jwt}"
  export OTEL_SERVICE_NAME="${service_name}"

  echo "Sending span via otel-cli..."

  otel-cli span \
    --name "test-operation-from-cli" \
    --service "${service_name}" \
    --kind client \
    --verbose \
    --attrs "${attrs}" && \
  echo "✅ Span sent successfully!"
  echo "🔍 Check Jaeger UI: https://jaeger.dev-tools.tigera.net/search?service=otel-cli-test-service&lookback=1h"
}

send_trace_with_curl() {
  local jwt="$1"               # JWT to use for Authorization header
  local service_name="${2:-otel-curl-test-service}"  # OTEL service name
  local attrs="${3:-test.attribute=example-value,environment=dev}" # Span attributes

  # --- Prepare OTEL trace payload ---
  local trace_id
  local span_id
  trace_id=$(openssl rand -hex 16)
  span_id=$(openssl rand -hex 8)

  # Parse attrs into JSON attributes array
  local attrs_json="[]"
  if [[ -n "$attrs" ]]; then
    # Split attrs by comma and build JSON array
    IFS=',' read -ra ATTR_PAIRS <<< "$attrs"
    local attr_items=()
    for pair in "${ATTR_PAIRS[@]}"; do
      IFS='=' read -r key value <<< "$pair"
      attr_items+=("$(printf '{"key":"%s","value":{"stringValue":"%s"}}' "$key" "$value")")
    done
    attrs_json="[$(IFS=,; echo "${attr_items[*]}")]"
  fi

  cat <<EOF > /tmp/otel-trace.json
{
  "resourceSpans": [
    {
      "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "$service_name"}}]},
      "scopeSpans": [
        {
          "spans": [
            {
              "traceId": "$trace_id",
              "spanId": "$span_id",
              "name": "test-operation-via-iap",
              "kind": 1,
              "startTimeUnixNano": "$(date +%s%N)",
              "endTimeUnixNano": "$(($(date +%s%N)+1000000))",
              "attributes": $attrs_json
            }
          ]
        }
      ]
    }
  ]
}
EOF

  curl -sS -X POST "$OTEL_EXPORTER_OTLP_ENDPOINT/v1/traces" \
    -H "Authorization: Bearer $jwt" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/otel-trace.json && \
  echo && echo "✅ Span sent successfully! Trace ID: $trace_id"

}

# Invoke trace sending
send_trace_with_cli "$IAP_JWT" "otel-cli-test-service" "test.attribute=example-value,environment=dev"
send_trace_with_curl "$IAP_JWT" "otel-curl-test-service" "test.attribute=example-value,environment=dev"

# Clean up
rm -f /tmp/claim.json /tmp/output.jwt

echo ""
echo "Note: otel-cli sends HTTP/protobuf by default. If you need JSON, use:"
echo "  export OTEL_EXPORTER_OTLP_PROTOCOL='http/json'"
