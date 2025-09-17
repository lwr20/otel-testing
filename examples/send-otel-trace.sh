#!/usr/bin/env bash
# send-otel-trace.sh
# Sends a test OpenTelemetry trace to Jaeger using otel-cli in a container.
# Then checks Jaeger for the trace by trace ID.

set -e

# Generate a unique trace ID
TRACE_ID=$(openssl rand -hex 16)
echo "Generated trace ID: $TRACE_ID"

# Send the trace with the specific trace ID

docker run --rm \
  --network host \
  ghcr.io/equinix-labs/otel-cli:latest \
  span \
  --endpoint http://localhost:4318 \
  --service test-service \
  --name test-span \
  --force-trace-id $TRACE_ID

echo -e "\nTest trace sent to Jaeger via otel-cli (container)."

# Wait a few seconds for the trace to be ingested
sleep 5

# Query Jaeger for the trace by trace ID
JAEGER_API="http://localhost:16686/api/traces/$TRACE_ID"
echo "Checking Jaeger for trace ID: $TRACE_ID ..."
RESPONSE=$(curl -s "$JAEGER_API")

if echo "$RESPONSE" | grep -q '"traceID"'; then
  echo "Trace $TRACE_ID found in Jaeger!"
else
  echo "Trace $TRACE_ID NOT found in Jaeger."
  exit 1
fi
