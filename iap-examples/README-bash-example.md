# OpenTelemetry Trace Example (Bash)

This example demonstrates sending OTLP traces to the Jaeger collector through Google IAP authentication using pure bash scripting.

## Features

- Generates IAP JWT using either `gcloud` or `openssl` (RS256 signing)
- Sends traces via two methods:
  - **otel-cli**: Using the otel-cli tool (HTTP/protobuf)
  - **curl**: Direct HTTP POST with OTLP JSON payload
- Modular functions for JWT signing and trace sending
- Support for custom service names and span attributes

## Prerequisites

### Required Tools

- `bash` (version 4.0 or later)
- `jq` - JSON processor
- `openssl` - For JWT signing and random ID generation
- `curl` - For HTTP requests

### Optional Tools

- `otel-cli` - OpenTelemetry command-line tool (download from [releases](https://github.com/equinix-labs/otel-cli/releases))
- `gcloud` - Google Cloud SDK (for gcloud-based JWT signing)

### Installation

```bash
# Install required packages (Debian/Ubuntu)
sudo apt-get install jq openssl curl

# Install otel-cli
wget https://github.com/equinix-labs/otel-cli/releases/download/v0.4.5/otel-cli_0.4.5_linux_amd64.tar.gz
tar -xzf otel-cli_0.4.5_linux_amd64.tar.gz
sudo mv otel-cli /usr/local/bin/
chmod +x /usr/local/bin/otel-cli

# Optional: Install gcloud CLI
# https://cloud.google.com/sdk/docs/install
```

### Service Account Setup

- Service account key file with IAP access to the OTLP endpoint
- Download the JSON key file from Google Cloud Console

## Usage

1. Update the configuration in `otel-test.sh`:

   ```bash
   export SERVICE_ACCOUNT_KEY="/path/to/your-service-account-key.json"
   export OTEL_EXPORTER_OTLP_ENDPOINT="https://your-collector.example.com"
   ```

2. Make the script executable:

   ```bash
   chmod +x otel-test.sh
   ```

3. Run the script:

   ```bash
   ./otel-test.sh
   ```

4. Check traces in Jaeger UI:
   - otel-cli traces: https://jaeger.dev-tools.tigera.net/search?service=otel-cli-test-service&lookback=1h
   - curl traces: https://jaeger.dev-tools.tigera.net/search?service=otel-curl-test-service&lookback=1h

## How it Works

### 1. JWT Generation

The script supports two JWT signing methods:

#### Option A: Using `gcloud` (requires Google Cloud SDK)

```bash
sign_jwt_gcloud()
```

- Creates JWT claims in `/tmp/claim.json`
- Uses `gcloud iam service-accounts sign-jwt` to sign
- Returns the signed JWT token

#### Option B: Using `openssl` (no gcloud dependency)

```bash
sign_jwt_openssl()
```

- Creates JWT header and payload
- Base64url encodes both parts
- Extracts private key from service account JSON
- Signs with `openssl dgst -sha256` (RS256 algorithm)
- Returns the complete JWT: `header.payload.signature`

**Toggle between methods** by commenting/uncommenting lines 91-95 in the script.

### 2. Trace Sending Methods

#### Method 1: Using otel-cli

```bash
send_trace_with_cli(jwt, service_name, attrs)
```

- Sets environment variables for otel-cli configuration
- Sends traces using HTTP/protobuf format (default)
- Simple command-line interface
- Automatically handles OTLP batching

**Example:**

```bash
send_trace_with_cli "$IAP_JWT" "my-service" "user=alice,action=login"
```

#### Method 2: Using curl

```bash
send_trace_with_curl(jwt, service_name, attrs)
```

- Manually constructs OTLP JSON payload
- Generates random trace and span IDs
- Parses comma-separated attributes into JSON format
- Sends HTTP POST to `/v1/traces` endpoint

**Example:**

```bash
send_trace_with_curl "$IAP_JWT" "my-service" "user=bob,action=logout"
```

### 3. JWT Claims Structure

Both signing methods create identical JWT claims:

```json
{
  "iss": "service-account@project.iam.gserviceaccount.com",
  "sub": "service-account@project.iam.gserviceaccount.com",
  "aud": "https://your-collector.example.com/*",
  "iat": 1699372800,
  "exp": 1699376400
}
```

- **iss** (issuer): Service account email
- **sub** (subject): Service account email
- **aud** (audience): OTLP endpoint URL with `/*` suffix (required by IAP)
- **iat** (issued at): Current Unix timestamp
- **exp** (expiration): Issued at + 3600 seconds (1 hour)

## Functions Reference

### `sign_jwt_gcloud()`

Generates IAP JWT using gcloud CLI.

**Returns:** JWT token string

**Requirements:** `gcloud` CLI installed and authenticated

### `sign_jwt_openssl()`

Generates IAP JWT using openssl (no gcloud dependency).

**Returns:** JWT token string

**Requirements:** `openssl`, `jq`, `base64`

### `send_trace_with_cli(jwt, service_name, attrs)`

Sends trace span using otel-cli.

**Parameters:**

- `jwt` - IAP JWT token for authentication
- `service_name` - OpenTelemetry service name (default: `otel-cli-test-service`)
- `attrs` - Comma-separated key=value attributes (default: `test.attribute=example-value,environment=dev`)

**Protocol:** HTTP/protobuf (OTLP standard)

### `send_trace_with_curl(jwt, service_name, attrs)`

Sends trace span using curl with OTLP JSON payload.

**Parameters:**

- `jwt` - IAP JWT token for authentication
- `service_name` - OpenTelemetry service name (default: `otel-curl-test-service`)
- `attrs` - Comma-separated key=value attributes (default: `test.attribute=example-value,environment=dev`)

**Protocol:** HTTP/JSON (OTLP alternative encoding)

**Generates:**

- Random 16-byte (32-char hex) trace ID
- Random 8-byte (16-char hex) span ID
- OTLP-compliant JSON payload at `/tmp/otel-trace.json`

## Customization Examples

### Send trace with custom attributes

```bash
send_trace_with_cli "$IAP_JWT" "my-app" "user.id=123,http.method=GET,http.status_code=200"
```

### Send trace to a different service

```bash
send_trace_with_curl "$IAP_JWT" "payment-service" "transaction.id=tx_456,amount=99.99"
```

### Use gcloud for JWT signing

Uncomment lines 91-93 and comment line 95:

```bash
if command -v gcloud &>/dev/null; then
  IAP_JWT=$(sign_jwt_gcloud)
else
  IAP_JWT=$(sign_jwt_openssl)
fi
```

## Troubleshooting

### JWT Authentication Errors (401 Unauthorized)

**Symptoms:**

- `HTTP 401` response from collector
- "Invalid JWT" or "Unauthorized" errors

**Solutions:**

1. Verify service account has IAP access to the endpoint
2. Check JWT audience format: `https://your-endpoint/*` (note the `/*` suffix)
3. Ensure JWT hasn't expired (check `iat` and `exp` claims)
4. Verify audience is a **string**, not an array (IAP is strict)
5. Confirm RS256 signing algorithm (not HS256)

**Debug JWT claims:**

```bash
# Decode JWT payload (between first and second dots)
echo "$IAP_JWT" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

### otel-cli Command Not Found

**Symptoms:**

- `otel-cli: command not found`

**Solutions:**

1. Install otel-cli from [releases](https://github.com/equinix-labs/otel-cli/releases)
2. Add to PATH or use absolute path
3. Comment out `send_trace_with_cli` call if not using otel-cli

### Connection Refused / Network Errors

**Symptoms:**

- `curl: (7) Failed to connect`
- Connection timeout errors

**Solutions:**

1. Verify OTLP endpoint is accessible: `curl -I https://your-endpoint`
2. Check firewall rules allow outbound HTTPS (443)
3. Ensure IAP is properly configured on the endpoint
4. Test without IAP first (if possible)

### Invalid JSON Payload

**Symptoms:**

- `HTTP 400 Bad Request`
- "Invalid OTLP payload" errors

**Solutions:**

1. Inspect generated JSON: `cat /tmp/otel-trace.json | jq .`
2. Verify trace/span IDs are valid hex strings
3. Check attribute parsing (comma-separated, no special chars in values)
4. Ensure timestamps are in nanoseconds: `date +%s%N`

### Base64 Encoding Issues

**Symptoms:**

- JWT signature verification fails
- "Malformed JWT" errors

**Solutions:**

1. Ensure base64url encoding (not standard base64):
   - Replace `+` with `-`
   - Replace `/` with `_`
   - Remove `=` padding
2. Use `openssl base64 -A` for no line wrapping
3. Check private key format (should be PKCS8 PEM)

## Output Explanation

### Successful Execution

```
✓ Generated IAP JWT
Sending span via otel-cli...
✅ Span sent successfully!
🔍 Check Jaeger UI: https://jaeger.dev-tools.tigera.net/search?service=otel-cli-test-service&lookback=1h

✅ Span sent successfully! Trace ID: 356219047a92c8cf657e41db7e69a50a

Note: otel-cli sends HTTP/protobuf by default. If you need JSON, use:
  export OTEL_EXPORTER_OTLP_PROTOCOL='http/json'
```

### Color Coding in Jaeger UI

Jaeger assigns consistent colors to each unique service name:

- **Blue/Green**: `otel-cli-test-service` traces
- **Yellow**: `otel-curl-test-service` traces
- **Other colors**: Additional services in your system

This visual distinction helps identify trace sources in distributed systems.

### OTLP Response

The curl method shows the OTLP collector response:

```json
{ "partialSuccess": {} }
```

An empty `partialSuccess` object indicates **all spans were accepted successfully** (no errors, no rejections).

## Advanced Usage

### Loop for Load Testing

```bash
# Send 100 traces
for i in {1..100}; do
  send_trace_with_cli "$IAP_JWT" "load-test" "iteration=$i"
  sleep 0.1
done
```

### Multiple Span Attributes

```bash
ATTRS="http.method=POST,http.url=/api/users,http.status_code=201,user.id=789,region=us-west"
send_trace_with_curl "$IAP_JWT" "api-service" "$ATTRS"
```

### Custom Span Timing

Modify the `send_trace_with_curl` function to add realistic timing:

```bash
local start_time=$(date +%s%N)
sleep 0.5  # Simulate 500ms operation
local end_time=$(date +%s%N)

# Use in JSON:
"startTimeUnixNano": "$start_time",
"endTimeUnixNano": "$end_time"
```

## Comparison to Go SDK Example

| Feature            | Bash (otel-test.sh)              | Go (otel-trace-example.go)  |
| ------------------ | -------------------------------- | --------------------------- |
| **Dependencies**   | System tools (jq, openssl, curl) | Go modules only             |
| **JWT Signing**    | gcloud or openssl                | Native Go crypto            |
| **OTLP Protocol**  | HTTP/protobuf (cli) or JSON      | HTTP/protobuf (SDK)         |
| **Span Creation**  | Command-line or JSON template    | Programmatic SDK API        |
| **Flexibility**    | Good for testing/debugging       | Production-ready            |
| **Batching**       | Manual (single span per call)    | Automatic (SDK batching)    |
| **Error Handling** | Basic exit codes                 | Comprehensive error types   |
| **Learning Curve** | Low (bash scripting)             | Medium (Go + OTLP concepts) |
| **Use Case**       | Testing, CI/CD, quick validation | Production instrumentation  |

## References

- [Google Cloud IAP Authentication](https://cloud.google.com/iap/docs/authentication-howto)
- [OpenTelemetry Protocol (OTLP)](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/otlp.md)
- [otel-cli Documentation](https://github.com/equinix-labs/otel-cli)
- [JWT RFC 7519](https://datatracker.ietf.org/doc/html/rfc7519)
- [RS256 Algorithm](https://datatracker.ietf.org/doc/html/rfc7518#section-3.3)
