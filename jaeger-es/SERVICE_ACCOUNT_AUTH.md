# Service Account Authentication for OTEL Endpoints

## Overview

Service account authentication allows applications to authenticate using JWT tokens instead of user OAuth2 flows. This solution provides **dual authentication**:

1. **OAuth2 for Users** - Browser-based authentication (existing)
2. **Service Account for Applications** - JWT token-based authentication (new)

## Architecture

```
Applications → Auth Middleware (4319) → Jaeger OTEL Endpoints
Users → OAuth2 Proxy (4318) → Jaeger OTEL Endpoints
```

## Complete Setup

### 1. Create Google Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project (same one used for OAuth2)
3. Go to "IAM & Admin" > "Service Accounts"
4. Click "Create Service Account"
5. Fill in details:
   - **Name**: `otel-trace-sender`
   - **Description**: `Service account for sending OTEL traces`
6. Click "Create and Continue"
7. Skip role assignment (click "Continue")
8. Click "Done"

### 2. Create Service Account Key

1. Click on the created service account
2. Go to "Keys" tab
3. Click "Add Key" > "Create new key"
4. Choose "JSON" format
5. Click "Create"
6. **Save as `service-account.json` in the jaeger-es directory**

### 3. Install Dependencies

```bash
# Install Python dependencies for auth middleware
pip install requests PyJWT

# Install jq for JSON parsing (if not already installed)
sudo apt-get install jq

# Install gcloud CLI (recommended for token generation)
# Follow: https://cloud.google.com/sdk/docs/install
```

### 4. Start the Enhanced Stack

```bash
# Use the enhanced docker-compose with auth middleware
docker-compose -f docker-compose-with-service-account.yml up -d
```

This starts:

- **Port 4318**: Service account-protected http endpoint
- **Port 4317**: Service account-protected gRPC endpoint
- **Port 16686**: Jaeger UI

### 5. Generate Service Account Token

```bash
./service-account-auth.sh
```

This will:

- Use your service account JSON file
- Generate a valid access token
- Show you how to use it

### 6. Test Service Account Authentication

```bash
# Method 1: Use the generated token
./send-otel-trace.sh

## Usage Examples

### For Applications (Service Account)

```bash
# Get access token
TOKEN=$(./service-account-auth.sh | grep "Access token" | cut -d: -f2 | xargs)

# Send trace
curl -X POST http://localhost:4319/v1/traces \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $TOKEN" \
     -d '{"resourceSpans":[...]}'
```

## Authentication Flow Details

### Service Account Flow

1. **Application** generates JWT token using service account key
2. **Auth Middleware** validates token with Google's API
3. **Request forwarded** to Jaeger if token is valid
4. **Trace ingested** into Elasticsearch

## File Structure

```
jaeger-es/
├── service-account.json             # Your service account key (create this)
├── service-account-auth.sh          # Generate access tokens
├── auth_middleware.py               # Custom auth middleware
├── docker-compose.yml  # Enhanced stack
├── send-otel-trace.sh  # Test service account auth
```

## Security Notes

- **Service account keys** should be stored securely and rotated regularly
- **Access tokens** expire after 1 hour and need regeneration
- **Production**: Use Google Workload Identity instead of key files

## Troubleshooting

### Service Account Issues

```bash
# Check service account file
jq . service-account.json

# Test token generation
./service-account-auth.sh

# Check auth middleware logs
docker-compose -f docker-compose-with-service-account.yml logs auth-middleware
```

### OAuth2 Issues

```bash
# Test OAuth2 flow
./simple-auth-test.sh

# Check OAuth2 proxy logs
docker-compose logs oauth2-proxy-http
```

## Benefits

✅ **Dual Authentication** - Supports both users and applications
✅ **No Session Cookies** - Service accounts use stateless JWT tokens
✅ **Google Integration** - Uses Google's robust authentication
✅ **Backward Compatible** - Existing OAuth2 flow still works
✅ **Production Ready** - Proper token validation and error handling
