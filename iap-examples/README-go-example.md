# OpenTelemetry Trace Example (Go)

This example demonstrates sending OTLP traces to the Jaeger collector through Google IAP authentication.

## Features

- Generates IAP JWT using service account credentials (RS256 signing)
- Sends traces via OTLP/HTTP with protobuf encoding
- Uses the official OpenTelemetry Go SDK

## Prerequisites

- Go 1.21 or later
- Service account key file with IAP access

## Usage

1. Update the service account key path in `otel-trace-example.go` if needed:

   ```go
   serviceAccountKeyPath := "/path/to/your-service-account-key.json"
   ```

2. Install dependencies:

   ```bash
   go mod download
   go mod tidy
   ```

3. Run the example:

   ```bash
   go run otel-trace-example.go
   ```

4. Check traces in Jaeger UI:
   https://jaeger.dev-tools.tigera.net/search?service=otel-go-test-service&lookback=1h

## How it works

1. **JWT Generation**: Reads the service account key and creates an RS256-signed JWT for IAP authentication
2. **OTLP Exporter**: Configures the OpenTelemetry HTTP exporter with the IAP JWT in headers
3. **Tracer Provider**: Sets up a tracer provider with resource attributes (service name, version, environment)
4. **Span Creation**: Creates a simple client span with custom attributes
5. **Export**: Batches and exports the span to the OTLP endpoint

## Comparison to otel-cli-test.sh

| Feature        | Bash (otel-cli)     | Go SDK                   |
| -------------- | ------------------- | ------------------------ |
| JWT Generation | openssl or gcloud   | Native Go crypto         |
| OTLP Support   | Via otel-cli binary | Native OpenTelemetry SDK |
| Span Creation  | Command-line args   | Programmatic API         |
| Dependencies   | External binaries   | Go modules only          |
| Flexibility    | Limited             | Full SDK capabilities    |

## Building a Binary

```bash
go build -o otel-trace-example otel-trace-example.go
./otel-trace-example
```
