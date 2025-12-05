#!/usr/bin/env bash
# send-otel-traces.sh
# Send OpenTelemetry spans to the OTLP/HTTP endpoint with realistic durations.
# Sends spans directly via HTTP POST with proper OTLP JSON encoding.

set -euo pipefail

# Defaults
COUNT_TRACES=5
SERVICE_NAME="bz-cli"
HTTP_ENDPOINT="http://172.18.0.2:30318"
HEADERS=""

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  -c, --count <n>              Number of traces to send (default: 5)
  -n, --service <name>         Service name (default: bz-cli)
  --http-endpoint <url>        OTLP HTTP endpoint (default: http://172.18.0.2:30318)
  -H, --headers <k=v[,k=v]>    HTTP headers (e.g., Authorization=Bearer TOKEN)
  -h, --help                   Show this help

Examples:
  $0                           # Send 5 traces
  $0 -c 10                     # Send 10 traces
  $0 -H "Authorization=Bearer TOKEN"   # Add auth header
USAGE
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--count) COUNT_TRACES="$2"; shift 2;;
    -n|--service) SERVICE_NAME="$2"; shift 2;;
    --http-endpoint) HTTP_ENDPOINT="$2"; shift 2;;
    -H|--headers) HEADERS="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 1;;
  esac
done

# Send a single trace via HTTP with proper OTLP JSON
send_trace_json() {
  local cmd="$1"
  local duration_ns="$2"

  # Generate IDs
  local trace_id
  trace_id=$(hexdump -vn16 -e '16/1 "%02x"' /dev/urandom)
  local parent_span_id
  parent_span_id=$(hexdump -vn8 -e '8/1 "%02x"' /dev/urandom)
  local child_span_id
  child_span_id=$(hexdump -vn8 -e '8/1 "%02x"' /dev/urandom)

  # Get current time in nanoseconds
  local end_ns
  end_ns=$(date +%s%N)
  local start_ns=$((end_ns - duration_ns))

  # Child span starts ~300ns after parent, ends ~50000ns before parent
  local child_start_ns=$((start_ns + 300))
  local child_end_ns=$((end_ns - 50000))

  # Decide if this trace should be errored (30% chance)
  local is_error=false
  local error_message=""
  local status_code=0
  if [[ $((RANDOM % 100)) -lt 30 ]]; then
    is_error=true
    status_code=2  # STATUS_CODE_ERROR in OTLP
    # Pick a random error message
    error_messages=(
      "connection timeout: failed to reach provisioner API"
      "authentication failed: invalid credentials"
      "resource not found: cluster does not exist"
      "quota exceeded: insufficient resources"
      "validation error: invalid configuration"
    )
    error_message="${error_messages[$((RANDOM % ${#error_messages[@]}))]}"
  fi

  echo "Sending trace: cmd=$cmd duration_us=$((duration_ns / 1000)) error=$is_error"

  # Generate random cluster name and directory
  local cluster_name="bz-calient-$(printf "%04d" $((RANDOM % 10000)))"
  local work_dir="/home/semaphore/banzai-calient/$(hexdump -vn8 -e '8/1 "%02x"' /dev/urandom)"

  # Create OTLP JSON payload using jq for proper JSON encoding and escaping
  local payload
  payload=$(jq -n \
    --arg service_name "$SERVICE_NAME" \
    --arg trace_id "$trace_id" \
    --arg parent_span_id "$parent_span_id" \
    --arg child_span_id "$child_span_id" \
    --arg start_ns "$start_ns" \
    --arg end_ns "$end_ns" \
    --arg child_start_ns "$child_start_ns" \
    --arg child_end_ns "$child_end_ns" \
    --arg cmd "$cmd" \
    --arg cluster_name "$cluster_name" \
    --arg work_dir "$work_dir" \
    --arg status_code "$status_code" \
    --arg error_message "$error_message" \
    '{
      "resourceSpans": [
        {
          "resource": {
            "attributes": [
              {
                "key": "service.name",
                "value": {"stringValue": $service_name}
              },
              {
                "key": "service.version",
                "value": {"stringValue": "v0.9.20-4-gf3301db85ee8"}
              }
            ]
          },
          "scopeSpans": [
            {
              "scope": {"name": "bz-cli"},
              "spans": [
                {
                  "traceId": $trace_id,
                  "spanId": $parent_span_id,
                  "name": ("bz " + $cmd),
                  "kind": 1,
                  "startTimeUnixNano": ($start_ns | tonumber),
                  "endTimeUnixNano": ($end_ns | tonumber),
                  "attributes": [
                    {"key": "command.args", "value": {"stringValue": ("[\"bz\",\"" + $cmd + "\"]")}},
                    {"key": "command.name", "value": {"stringValue": ("bz " + $cmd)}},
                    {"key": "command.subcommand", "value": {"stringValue": $cmd}},
                    {"key": "command.working_directory", "value": {"stringValue": $work_dir}},
                    {"key": "internal.span.format", "value": {"stringValue": "otlp"}},
                    {"key": "otel.scope.name", "value": {"stringValue": "bz-cli"}},
                    {"key": "span.kind", "value": {"stringValue": "internal"}}
                  ],
                  "status": (
                    if ($status_code | tonumber) == 2 then
                      {"code": 2, "message": $error_message}
                    else
                      {"code": 0}
                    end
                  )
                },
                {
                  "traceId": $trace_id,
                  "spanId": $child_span_id,
                  "parentSpanId": $parent_span_id,
                  "name": $cmd,
                  "kind": 1,
                  "startTimeUnixNano": ($child_start_ns | tonumber),
                  "endTimeUnixNano": ($child_end_ns | tonumber),
                  "attributes": [
                    {"key": "cluster.name", "value": {"stringValue": $cluster_name}},
                    {"key": "command.args", "value": {"stringValue": "[]"}},
                    {"key": "command.containerize", "value": {"boolValue": false}},
                    {"key": "command.dry_run", "value": {"boolValue": false}},
                    {"key": "command.name", "value": {"stringValue": ("bz " + $cmd)}},
                    {"key": "command.skip_prompt", "value": {"boolValue": false}},
                    {"key": "command.subcommand", "value": {"stringValue": $cmd}},
                    {"key": "command.verbose", "value": {"boolValue": false}},
                    {"key": "command.working_directory", "value": {"stringValue": $work_dir}},
                    {"key": "internal.span.format", "value": {"stringValue": "otlp"}},
                    {"key": "otel.scope.name", "value": {"stringValue": "bz-cli"}},
                    {"key": "provisioner.type", "value": {"stringValue": "gcp-mke"}},
                    {"key": "span.kind", "value": {"stringValue": "internal"}}
                  ],
                  "status": (
                    if ($status_code | tonumber) == 2 then
                      {"code": 2, "message": $error_message}
                    else
                      {"code": 0}
                    end
                  )
                }
              ]
            }
          ]
        }
      ]
    }')

  # Send via HTTP POST
  curl -s -X POST \
    -H "Content-Type: application/json" \
    ${HEADERS:+-H "$HEADERS"} \
    -d "$payload" \
    "$HTTP_ENDPOINT/v1/traces" \
    > /dev/null 2>&1 || true
}

# Commands and their typical durations (in nanoseconds)
declare -A COMMAND_DURATIONS=(
  ["install"]=500000000000   # 500 seconds in nanoseconds
  ["destroy"]=150000000000   # 150 seconds
  ["tests"]=130000000000     # 130 seconds
  ["diags"]=30000000000      # 30 seconds
)

# Send traces
for ((i=1; i<=COUNT_TRACES; i++)); do
  # Pick a random command
  commands=("${!COMMAND_DURATIONS[@]}")
  cmd=${commands[$((RANDOM % ${#commands[@]}))]}
  duration_ns=${COMMAND_DURATIONS[$cmd]}

  # Add variance (±20%)
  variance=$(( (RANDOM % 40 - 20) ))
  duration_ns=$(( duration_ns + (duration_ns * variance / 100) ))

  send_trace_json "$cmd" "$duration_ns"
  sleep 0.1
done

echo "Done. Sent $COUNT_TRACES traces over HTTP to $HTTP_ENDPOINT"
