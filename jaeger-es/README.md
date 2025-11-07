# Service Account Protected OpenTelemetry Endpoints

This setup adds Google Service Account authentication to the OpenTelemetry collector endpoints (ports 4317 and 4318) using a custom authentication middleware.

## Architecture

```
Client → Auth Middleware (4317/4318) → Jaeger OTEL Endpoints → Elasticsearch
```

- **Auth Middleware**: Validates Google Service Account JWT tokens for OTEL endpoints
- **Jaeger**: Receives authenticated traces and stores them in Elasticsearch
- **Elasticsearch**: Stores trace data
- **Kibana**: Provides UI for viewing traces

## Quick Start Guide

### 1. Set up Google Service Account

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Create a service account:
   - Go to "IAM & Admin" > "Service Accounts"
   - Click "Create Service Account"
   - Give it a name and description
   - Click "Create and Continue"
   - Add any necessary roles (optional for basic usage)
   - Click "Done"
4. Create a JSON key:
   - Click on your newly created service account
   - Go to the "Keys" tab
   - Click "Add Key" > "Create new key"
   - Choose "JSON" and click "Create"
   - Save the downloaded JSON file as `service-account.json` in this directory

### 2. Start the Stack

```bash
# Start all services
docker-compose up -d

# Or use the enhanced service account version
docker-compose -f docker-compose-with-service-account.yml up -d
```

### 3. Test the Setup

Run the test script:

```bash
./send-otel-trace.sh
```

This will:

1. Generate a Google Service Account access token
2. Send a test trace to the protected endpoint with Bearer token authentication
3. Verify the trace appears in Jaeger

## Authentication Methods

### Service Account Authentication

Applications authenticate using Google Service Account JSON keys:

1. **Get Access Token**: Use `./service-account-auth.sh` to generate an access token
2. **Send Traces**: Include the token in the `Authorization: Bearer` header
3. **Example**:
   ```bash
   # Get token
   ACCESS_TOKEN=$(./service-account-auth.sh | tail -1)
   
   # Send trace with authentication
   curl -X POST http://localhost:4318/v1/traces \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -d '{"resourceSpans": [...]}'
   ```

### Manual Token Generation

You can also generate tokens manually using gcloud:

```bash
# Activate service account
gcloud auth activate-service-account --key-file=service-account.json

# Get access token
gcloud auth print-access-token
```

## Services and Ports

| Service           | Port  | Description                                    |
| ----------------- | ----- | ---------------------------------------------- |
| Auth Middleware   | 4317  | Service Account protected OTLP gRPC endpoint  |
| Auth Middleware   | 4318  | Service Account protected OTLP HTTP endpoint  |
| Jaeger UI         | 16686 | Jaeger web interface                           |
| Jaeger Collector  | 14268 | Direct Jaeger HTTP (unprotected)              |
| Elasticsearch     | 9200  | Elasticsearch API                              |
| Kibana            | 5601  | Kibana web interface                           |

## Configuration Files

- `auth_middleware.py`: Custom authentication middleware for service accounts
- `Dockerfile`: Container build for the authentication middleware
- `service-account-auth.sh`: Script to generate service account tokens
- `service-account.json`: Your Google Service Account credentials
- `docker-compose.yml`: Main service orchestration
- `docker-compose-with-service-account.yml`: Enhanced service account configuration

## Testing Scripts

- `send-otel-trace.sh`: Send test traces with service account authentication
- `send-otel-trace-with-service-account.sh`: Alternative service account testing script

## Service Account Features

- **Stateless Authentication**: No session cookies, tokens are validated per request
- **Application-to-Application**: Designed for service-to-service communication
- **Google Cloud Integration**: Works seamlessly with Google Cloud services
- **JWT Token Validation**: Validates tokens using Google's public keys
- **Scalable**: No session state to manage across multiple instances

## Troubleshooting

### Common Issues

1. **"Invalid service account token"**
   - Ensure your `service-account.json` file is valid
   - Check that the service account has not been disabled
   - Verify the token hasn't expired (default: 1 hour)

2. **"Authentication required"**
   - Make sure you're including the `Authorization: Bearer` header
   - Verify the token format is correct

3. **"service-account.json not found"**
   - Download the service account key from Google Cloud Console
   - Place it in the same directory as the scripts

### Debug Steps

1. Check auth middleware logs:
   ```bash
   docker-compose logs auth-middleware
   ```

2. Test service account token generation:
   ```bash
   ./service-account-auth.sh
   ```

3. Verify authentication middleware is running:
   ```bash
   curl -v http://localhost:4318/v1/traces
   # Should return 401 without authentication
   ```

4. Test with authentication:
   ```bash
   ACCESS_TOKEN=$(./service-account-auth.sh | tail -1)
   curl -v -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost:4318/v1/traces
   ```

## Production Considerations

- **Token Rotation**: Implement automatic token refresh for long-running applications
- **Monitoring**: Monitor authentication failures and token expiration
- **Security**: Store service account keys securely, never in version control
- **Access Control**: Use IAM roles to restrict service account permissions
- **Logging**: Enable audit logging for authentication events

## Service Account Documentation

For detailed service account setup and usage, see:
- [SERVICE_ACCOUNT_AUTH.md](SERVICE_ACCOUNT_AUTH.md) - Comprehensive service account guide