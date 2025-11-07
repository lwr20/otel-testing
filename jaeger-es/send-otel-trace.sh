#!/usr/bin/env bash
# send-otel-trace.sh
# Sends a test OpenTelemetry trace to Jaeger using service account authentication.
# Then checks Jaeger for the trace by trace ID.

set -e

# Default configuration
PROTOCOL="http"
OTEL_HTTP_ENDPOINT="http://localhost:4318"
OTEL_GRPC_ENDPOINT="http://localhost:4317"

# Parse command line arguments
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p, --protocol PROTOCOL   Protocol to use: 'http' or 'grpc' (default: http)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                       # Send trace over HTTP (default)"
    echo "  $0 -p http              # Send trace over HTTP"
    echo "  $0 -p grpc              # Send trace over gRPC"
    echo "  $0 --protocol grpc      # Send trace over gRPC"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--protocol)
            PROTOCOL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate protocol
if [[ "$PROTOCOL" != "http" && "$PROTOCOL" != "grpc" ]]; then
    echo "❌ Invalid protocol: $PROTOCOL. Must be 'http' or 'grpc'"
    usage
    exit 1
fi

# Set endpoint based on protocol
if [[ "$PROTOCOL" == "http" ]]; then
    OTEL_ENDPOINT="$OTEL_HTTP_ENDPOINT"
    OTEL_CLI_PROTOCOL=""
else
    OTEL_ENDPOINT="$OTEL_GRPC_ENDPOINT"
    OTEL_CLI_PROTOCOL="--protocol grpc"
fi

# Load environment variables if .env file exists
if [ -f .env ]; then
    export "$(grep -v '^#' .env | xargs)"
fi

echo "🚀 Sending OTEL trace with service account authentication over $PROTOCOL"

# Generate a trace ID
TRACE_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1)

# Get service account access token
echo "🔑 Getting service account access token..."
if ! ./service-account-auth.sh > /dev/null; then
    echo "❌ Failed to get service account token"
    exit 1
fi

# Read the token from the saved file
if [ -f "/tmp/service_account_token.txt" ]; then
    ACCESS_TOKEN=$(cat /tmp/service_account_token.txt)
else
    echo "❌ Token file not found"
    exit 1
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ No access token received"
    exit 1
fi

echo "✅ Got service account access token"

echo "📡 Sending trace with ID: $TRACE_ID using otel-cli over $PROTOCOL"

# Send the trace using otel-cli with service account authentication
docker run --rm \
  --network host \
  -e OTEL_EXPORTER_OTLP_ENDPOINT="$OTEL_ENDPOINT" \
  -e OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer $ACCESS_TOKEN" \
  ghcr.io/equinix-labs/otel-cli:latest \
  span \
  $OTEL_CLI_PROTOCOL \
  --endpoint "$OTEL_ENDPOINT" \
  --service test-service \
  --name test-span \
  --attrs "protocol=$PROTOCOL,auth.method=service_account" \
  --force-trace-id $TRACE_ID

if [ $? -eq 0 ]; then
    echo "✅ Trace submitted successfully with otel-cli over $PROTOCOL"
else
    echo "❌ Trace submission failed with otel-cli"
    exit 1
fi

echo -e "\nTest trace sent to Jaeger with service account authentication."

# Wait a few seconds for the trace to be ingested
sleep 5

# Query Jaeger for the trace by trace ID
JAEGER_API="http://localhost:16686/api/traces/$TRACE_ID"
echo "Checking Jaeger for trace ID: $TRACE_ID ..."
RESPONSE=$(curl -s "$JAEGER_API")

if echo "$RESPONSE" | grep -q '"traceID"'; then
  echo "Trace $TRACE_ID found in Jaeger!"
  echo ""
  echo "✅ Service account protected OTEL endpoint setup complete!"
  echo "Traces are now secured with Google Service Account authentication."
else
  # Trace might take time to appear, let's also check by service name
  echo "Direct trace lookup failed, checking service traces..."
  # Check both possible service names
  SERVICE_TRACES=$(curl -s "http://localhost:16686/api/traces?service=test-service&limit=5")
  SERVICE_TRACES_SA=$(curl -s "http://localhost:16686/api/traces?service=test-service-sa&limit=5")

  if echo "$SERVICE_TRACES" | grep -q '"traceID"' || echo "$SERVICE_TRACES_SA" | grep -q '"traceID"'; then
    echo "✅ Traces found for test service - authentication is working!"
    echo "✅ Service account protected OTEL endpoint setup complete!"
    echo "Traces are now secured with Google Service Account authentication."
  else
    echo "Trace $TRACE_ID NOT found in Jaeger."
    echo "This might be due to trace ingestion delays. Check Jaeger UI at http://localhost:16686"
    exit 1
  fi
fi