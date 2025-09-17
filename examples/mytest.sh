#!/bin/bash

set -e
set -x

carrier=./carrier    # traceparent propagation via tempfile
sockfile=./sockfile

export OTEL_SERVICE_NAME="otel-mytest-demo"
export OTEL_EXPORTER_OTLP_ENDPOINT=grpc://localhost:4317

# # First, get a trace and span ID. We need to get one now so we can propagate it to the child
# # Get trace ID from TRACEPARENT, if present
# tid="$(<<<${TRACEPARENT:-} cut -d- -f2)"
# tid="${tid:-"$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)"}"
# Always generate a new span ID
# sid="$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)"

# # Execute the command they wanted with the propagation through TRACEPARENT
# TRACEPARENT="00-${tid}-${sid}-01" "${@:2}"

# start the span background server, set up trace propagation, and
# time out after 10 seconds (which shouldn't be reached)
sockdir=$(mktemp -d) # a unix socket will be created here
sid="$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)"
../otel-cli span background \
    --verbose --fail \
    --sockdir $sockdir \
    --name "script execution" \
    --tp-carrier $carrier \
    --timeout 60 &
echo "$sockdir" >> $sockfile

sockdir=$(tail -n 1 $sockfile)
../otel-cli span event \
    --verbose \
    --name "sync" \
    --sockdir "$sockdir"

data1=$(uuidgen)

# add an event to the span running in the background, with an attribute
# set to the uuid we just generated

sockdir=$(tail -n 1 $sockfile)
../otel-cli span event \
    --verbose \
    --name "did a thing" \
    --sockdir "$sockdir" \
    --attrs "data1=$data1"

# waste some time
sleep 1

# add an event that says we wasted some time
sockdir=$(tail -n 1 $sockfile)
../otel-cli span event \
    --verbose \
    --name "slept 1 second" \
    --sockdir "$sockdir"

# attempt to do a nested span
sockdir=$(mktemp -d) # a unix socket will be created here
sid="$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)"
../otel-cli span background \
    --verbose --fail \
    --sockdir "$sockdir" \
    --name "nested span?" \
    --tp-carrier $carrier \
    --force-span-id "$sid" &
echo "$sockdir" >> $sockfile

sleep 0.2

sockdir=$(tail -n 1 $sockfile)
../otel-cli span event --verbose --name "slept 0.2 second" --sockdir "$sockdir"

# attempt to do a nested span
sockdir=$(mktemp -d) # a unix socket will be created here
sid="$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)"

../otel-cli span background \
    --verbose --fail \
    --sockdir "$sockdir" \
    --name "nested nested span" \
    --tp-carrier $carrier \
    --force-span-id "$sid" &
echo "$sockdir" >> $sockfile

sockdir=$(tail -n 1 $sockfile)
../otel-cli span event --verbose --name "event in nested nested span" --sockdir "$sockdir"

sockdir=$(tail -n 1 $sockfile)
../otel-cli span end --sockdir "$sockdir"
sed -i '$d' $sockfile

sockdir=$(tail -n 1 $sockfile)
../otel-cli span event --verbose --name "event in nested span" --sockdir "$sockdir"

sockdir=$(tail -n 1 $sockfile)
../otel-cli span end --sockdir "$sockdir"
sed -i '$d' $sockfile

# run a shorter sleep inside a child span, using a carrier file for propagation
# carrier=$(mktemp)
# export TRACEPARENT="00-${tid}-${sid}-01"
# echo "export TRACEPARENT=$TRACEPARENT" > "$carrier"
# ../otel-cli exec \
#     --verbose --fail \
#     --name "sleep 0.2" \
#     --tp-carrier "$carrier" \
#     --force-trace-id "$tid" \
#     sleep 0.2
# rm "$carrier"

# finally, tell the background server we're all done and it can exit
sockdir=$(tail -n 1 $sockfile)
../otel-cli span end --sockdir "$sockdir"
sed -i '$d' $sockfile

rm "$carrier"