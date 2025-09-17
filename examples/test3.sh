#!/bin/bash

export OTEL_SERVICE_NAME="otel-thoth-demo"
export OTEL_RESOURCE_ATTRIBUTES=foo=bar,baz=foo
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
. otel.sh
task default
