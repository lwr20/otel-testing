#!/bin/bash
# service-account-auth.sh - Generate JWT tokens from Google Service Account

set -e

SERVICE_ACCOUNT_FILE="service-account.json"
TOKEN_FILE="/tmp/service_account_token.txt"

echo "🔑 Google Service Account JWT Token Generator"
echo "============================================="
echo ""

# Check if service account file exists
if [ ! -f "$SERVICE_ACCOUNT_FILE" ]; then
    echo "❌ Service account file not found: $SERVICE_ACCOUNT_FILE"
    echo ""
    echo "📋 To create a service account file:"
    echo "1. Go to Google Cloud Console > IAM & Admin > Service Accounts"
    echo "2. Create a new service account (or use existing)"
    echo "3. Create a JSON key for the service account"
    echo "4. Save the JSON file as '$SERVICE_ACCOUNT_FILE' in this directory"
    echo ""
    exit 1
fi

echo "📄 Found service account file: $SERVICE_ACCOUNT_FILE"

# Extract service account details
CLIENT_EMAIL=$(jq -r '.client_email' "$SERVICE_ACCOUNT_FILE" 2>/dev/null || echo "")
PRIVATE_KEY=$(jq -r '.private_key' "$SERVICE_ACCOUNT_FILE" 2>/dev/null || echo "")
PRIVATE_KEY_ID=$(jq -r '.private_key_id' "$SERVICE_ACCOUNT_FILE" 2>/dev/null || echo "")

if [ -z "$CLIENT_EMAIL" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Invalid service account file format"
    exit 1
fi

echo "📧 Service account: $CLIENT_EMAIL"
echo ""

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "❌ jq is required but not installed"
    echo "   Install with: sudo apt-get install jq"
    exit 1
fi

# Generate JWT token
echo "🔄 Generating JWT access token..."

# Use gcloud if available (easier method)
if command -v gcloud &> /dev/null; then
    echo "🎯 Using gcloud to generate access token..."

    # Activate service account
    gcloud auth activate-service-account "$CLIENT_EMAIL" --key-file="$SERVICE_ACCOUNT_FILE" 2>/dev/null

    # Get access token
    ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null)

    if [ -n "$ACCESS_TOKEN" ]; then
        echo "✅ Successfully generated access token!"
        echo ""
        echo "🎯 You can now use this token with the OTEL endpoints:"
        echo ""
        echo "   export SERVICE_ACCOUNT_TOKEN=\"$ACCESS_TOKEN\""
        echo "   ./send-otel-trace-with-service-account.sh"
        echo ""
        echo "📋 Access token (copy this):"
        echo "$ACCESS_TOKEN"

        # Save token to file
        echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
        echo ""
        echo "💾 Token saved to: $TOKEN_FILE"

        exit 0
    else
        echo "❌ Failed to generate access token with gcloud"
    fi
fi

echo "⚠️  gcloud not available, trying manual JWT generation..."
echo "   Note: This requires additional dependencies"

# Manual JWT generation (more complex, requires additional tools)
echo ""
echo "💡 For manual JWT generation, you need:"
echo "   1. Install gcloud CLI (recommended): https://cloud.google.com/sdk/docs/install"
echo "   2. Or use a JWT library for bash (complex)"
echo ""
echo "🚀 Recommended: Install gcloud CLI and re-run this script"