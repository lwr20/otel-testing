#!/bin/bash
# test-grafana-tempo.sh: Send test traces to Tempo using otel-cli and verify retrieval via Tempo's API
set -euo pipefail

QUERY_ENDPOINT="http://localhost:3200/api/traces"

# Generate random trace IDs
TRACE_ID_SUCCESS=$(openssl rand -hex 16)
TRACE_ID_FAILURE=$(openssl rand -hex 16)

echo "Sending successful test trace to Tempo using otel-cli..."

# Send a successful trace
otel-cli span \
  --endpoint http://localhost:4318 \
  --service test-grafana-tempo \
  --name "successful-span" \
  --force-trace-id "$TRACE_ID_SUCCESS" \
  --attrs "test.key=test-value,environment=testing,status=ok"

echo "Sending failing test trace to Tempo using otel-cli..."

# Send a failing trace
otel-cli span \
  --endpoint http://localhost:4318 \
  --service test-grafana-tempo \
  --name "failed-span" \
  --force-trace-id "$TRACE_ID_FAILURE" \
  --attrs "test.key=test-value,environment=testing,status=error" \
  --status-code error \
  --status-description "Test failure"

echo "Traces sent - Success ID: $TRACE_ID_SUCCESS, Failure ID: $TRACE_ID_FAILURE"

sleep 5

echo "Querying Tempo for successful trace..."
RESPONSE_SUCCESS=$(curl -s "${QUERY_ENDPOINT}/$TRACE_ID_SUCCESS")

echo "Querying Tempo for failed trace..."
RESPONSE_FAILURE=$(curl -s "${QUERY_ENDPOINT}/$TRACE_ID_FAILURE")

if echo "$RESPONSE_SUCCESS" | grep -q "$TRACE_ID_SUCCESS"; then
  echo "Successful trace ingested and retrieved!"
else
  echo "Successful trace not found in Tempo."
fi

if echo "$RESPONSE_FAILURE" | grep -q "$TRACE_ID_FAILURE"; then
  echo "Failed trace ingested and retrieved!"
else
  echo "Failed trace not found in Tempo."
fi

echo "Check the 'Test Grafana Tempo - Span Status' dashboard in Grafana to see the visualization!"
