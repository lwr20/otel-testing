#!/usr/bin/env bash
# send-otel-trace.sh
# Sends a test OpenTelemetry trace to the OTEL Collector using otel-cli in a container.
# Then checks Jaeger for the trace.

set -e

# Use otel/opentelemetry-collector-contrib image to run otel-cli
# This avoids local installation and works cross-platform

docker run --rm \
  --network host \
  ghcr.io/equinix-labs/otel-cli:latest \
  span \
  --endpoint http://localhost:4318 \
  --service test-service \
  --name test-span \
  --attrs "test.key=test-value"

echo -e "\nTest trace sent to OTEL Collector via otel-cli (container)."

# Wait a few seconds for the trace to be ingested
sleep 5

# Query Jaeger for the trace
JAEGER_API="http://localhost:16686/api/traces?service=test-service&limit=1"
echo "Checking Jaeger for traces from 'test-service'..."
RESPONSE=$(curl -s "$JAEGER_API")

if echo "$RESPONSE" | grep -q '"traceID"'; then
  echo "Trace found in Jaeger!"
else
  echo "Trace NOT found in Jaeger."
  exit 1
fi
