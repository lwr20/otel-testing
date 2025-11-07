#!/bin/bash
# simple-trace-test.sh - Simple script to send OTEL trace and search in ES

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SERVICE_NAME="test-service"
OPERATION_NAME="test-operation"
OTEL_HTTP_ENDPOINT="http://localhost:4318"  # Jaeger OTLP HTTP
OTEL_GRPC_ENDPOINT="localhost:4317"  # Jaeger OTLP GRPC
JAEGER_API="http://localhost:16686"
ELASTICSEARCH_URL="http://localhost:9200"

echo -e "${BLUE}🚀 OTEL Trace Test${NC}"
echo "=================="
echo ""

for protocol in "http" "grpc"; do
    if [ "$protocol" == "http" ]; then
        OTEL_ENDPOINT="$OTEL_HTTP_ENDPOINT"
        OTEL_CLI_PROTOCOL="http"
    else
        OTEL_ENDPOINT="$OTEL_GRPC_ENDPOINT"
        OTEL_CLI_PROTOCOL="grpc"
    fi

    echo -e "${YELLOW}📡 Sending trace over $protocol...${NC}"

    # Generate unique trace ID
    TRACE_ID=$(openssl rand -hex 16)
    SPAN_ID=$(openssl rand -hex 8)

    echo "Generated Trace ID: $TRACE_ID"
    echo "Span ID: $SPAN_ID"
    echo "Service: $SERVICE_NAME"
    echo "Operation: $OPERATION_NAME"
    echo ""

    # Check if otel-cli is available
    if command -v otel-cli &> /dev/null; then
        OTEL_CMD="otel-cli"
    else
        OTEL_CMD="docker run --rm --network host ghcr.io/equinix-labs/otel-cli:latest"
    fi

    echo -e "${YELLOW}📡 Sending trace...${NC}"
    echo "Command: $OTEL_CMD span --endpoint \"$OTEL_ENDPOINT\" --service \"$SERVICE_NAME\" --name \"$OPERATION_NAME\" --force-trace-id \"$TRACE_ID\" --force-span-id \"$SPAN_ID\" --attrs \"test=true,environment=k8s\""

    if $OTEL_CMD span \
        --endpoint "$OTEL_ENDPOINT" \
        --service "$SERVICE_NAME" \
        --name "$OPERATION_NAME" \
        --force-trace-id "$TRACE_ID" \
        --force-span-id "$SPAN_ID" \
        --attrs "test=true,environment=k8s,proto=$OTEL_CLI_PROTOCOL"; then
        echo -e "${GREEN}✅ Trace sent successfully${NC}"
    else
        echo -e "${RED}❌ Failed to send trace${NC}"
        echo "Let's try debugging the endpoint..."

        echo "Testing endpoint connectivity:"
        curl -v "$OTEL_ENDPOINT/v1/traces" -X POST -H "Content-Type: application/json" -d '{"resourceSpans": []}'

        exit 1
    fi

    echo ""
    echo -e "${YELLOW}⏳ Waiting 3 seconds for ingestion...${NC}"
    sleep 3

    echo ""
    echo -e "${YELLOW}🔍 Searching in Jaeger...${NC}"

    # Determine API path
    if curl -s "http://localhost:16686/jaeger/api/services" | grep -q "data" 2>/dev/null; then
        API_PATH="/jaeger/api"
    else
        API_PATH="/api"
    fi

    echo "Using API path: $API_PATH"

    # Search in Jaeger
    jaeger_result=$(curl -s "$JAEGER_API$API_PATH/traces/$TRACE_ID")
    echo "Jaeger API response: $jaeger_result"

    if echo "$jaeger_result" | jq -e '.data[0].traceID' > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Found trace in Jaeger!${NC}"
        service_name=$(echo "$jaeger_result" | jq -r '.data[0].processes | to_entries[0].value.serviceName')
        span_count=$(echo "$jaeger_result" | jq '.data[0].spans | length')
        echo "  Service: $service_name"
        echo "  Spans: $span_count"
        JAEGER_FOUND=true
    else
        echo -e "${RED}❌ Trace not found in Jaeger${NC}"
        JAEGER_FOUND=false
    fi

    echo ""
    echo -e "${YELLOW}🗄️ Searching in Elasticsearch...${NC}"

    # Search in Elasticsearch with different possible field names
    es_queries=(
        "{\"query\": {\"term\": {\"traceID\": \"$TRACE_ID\"}}}"
        "{\"query\": {\"term\": {\"traceId\": \"$TRACE_ID\"}}}"
        "{\"query\": {\"term\": {\"trace_id\": \"$TRACE_ID\"}}}"
    )

    ES_FOUND=false
    for query in "${es_queries[@]}"; do
        echo "Trying query: $query"
        es_result=$(curl -s -X POST "$ELASTICSEARCH_URL/jaeger-*/_search" \
            -H "Content-Type: application/json" \
            -d "$query")

        echo "ES response: $es_result"
        hit_count=$(echo "$es_result" | jq -r '.hits.total.value // .hits.total // 0')
        if [ "$hit_count" -gt 0 ]; then
            echo -e "${GREEN}✅ Found trace in Elasticsearch!${NC}"
            echo "  Documents: $hit_count"
            index_name=$(echo "$es_result" | jq -r '.hits.hits[0]._index')
            echo "  Index: $index_name"
            ES_FOUND=true
            break
        fi
    done

    if [ "$ES_FOUND" = false ]; then
        echo -e "${RED}❌ Trace not found in Elasticsearch${NC}"

        # Show debugging info
        echo ""
        echo "Debugging - Available Jaeger indices:"
        curl -s "$ELASTICSEARCH_URL/_cat/indices/jaeger-*?v" | head -5

        total_docs=$(curl -s "$ELASTICSEARCH_URL/jaeger-*/_search?size=0" | jq -r '.hits.total.value // .hits.total // 0')
        echo "Total documents in Jaeger indices: $total_docs"
    fi

    echo ""
    echo -e "${BLUE}📋 Summary${NC}"
    echo "==========="
    echo "Trace ID: $TRACE_ID"

    if [ "$JAEGER_FOUND" = true ] && [ "$ES_FOUND" = true ]; then
        echo -e "${GREEN}🎉 SUCCESS: Trace found in both Jaeger and Elasticsearch!${NC}"
        echo "Complete pipeline working: OTEL Collector → Jaeger → Elasticsearch"
    elif [ "$JAEGER_FOUND" = true ]; then
        echo -e "${YELLOW}⚠️ PARTIAL: Found in Jaeger but not Elasticsearch${NC}"
        echo "Storage or indexing issue possible"
    else
        echo -e "${RED}❌ FAILED: Trace not found${NC}"
    fi

    echo ""
    echo -e "${BLUE}🔗 Access URLs:${NC}"
    echo "Jaeger UI: http://localhost:16686/jaeger/trace/$TRACE_ID"
    echo "Jaeger API: curl -s \"$JAEGER_API$API_PATH/traces/$TRACE_ID\" | jq ."
    echo "ES Search: curl -s -X POST \"$ELASTICSEARCH_URL/jaeger-*/_search\" -H \"Content-Type: application/json\" -d '{\"query\": {\"term\": {\"traceID\": \"$TRACE_ID\"}}}' | jq ."
    if [ "$JAEGER_FOUND" = true ] && [ "$ES_FOUND" = true ]; then
        echo Next...
    else
        exit 1
    fi
done
