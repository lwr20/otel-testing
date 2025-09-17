function tracing::run() {
  # Throughout, "local" usage is critical to avoid nested calls overwriting things
  local start="$(date -u +%s.%N)"
  # First, get a trace and span ID. We need to get one now so we can propagate it to the child
  # Get trace ID from TRACEPARENT, if present
  local tid="$(<<<${TRACEPARENT:-} cut -d- -f2)"
  tid="${tid:-"$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)"}"
  # Always generate a new span ID
  local sid="$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)"

  # Execute the command they wanted with the propagation through TRACEPARENT
  TRACEPARENT="00-${tid}-${sid}-01" "${@:2}"

  local end="$(date -u +%s.%N)"

  # Now report this span. We override the IDs to the ones we set before.
  # TODO: support attributes
  ../otel-cli span \
    --service "${BASH_SOURCE[-1]}" \
    --name "$1" \
    --start "$start" \
    --end "$end" \
    --force-trace-id "$tid" \
    --force-span-id "$sid"
}


function nested() {
  tracing::run "child1" sleep .1
  tracing::run "child2" sleep .2
  tracing::run "deep" deep
}

function deep() {
  tracing::run "in-deep" sleep .1
}

export OTEL_SERVICE_NAME="otel-testing-demo"
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
tracing::run "parent" nested
