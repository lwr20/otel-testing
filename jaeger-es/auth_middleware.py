#!/usr/bin/env python3
"""
auth_middleware.py - Custom authentication middleware for OTEL endpoints

Supports Google Service Account JWT tokens for applications.
"""

import json
import jwt
import requests
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import os

# Configuration
JAEGER_OTEL_ENDPOINT = "http://jaeger:4318"
LISTEN_PORT = 4319  # Port for our middleware


class AuthMiddleware(BaseHTTPRequestHandler):

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def do_PUT(self):
        self.handle_request()

    def do_DELETE(self):
        self.handle_request()

    def handle_request(self):
        """Handle incoming requests with service account authentication"""

        # Check for service account authentication
        auth_header = self.headers.get("Authorization", "")

        if auth_header.startswith("Bearer "):
            token = auth_header[7:]  # Remove 'Bearer ' prefix

            if self.validate_service_account_token(token):
                print(f"✅ Service account authentication successful for {self.path}")
                self.proxy_to_jaeger()
                return
            else:
                print(f"❌ Invalid service account token for {self.path}")
                self.send_error(401, "Invalid service account token")
                return

        # No valid authentication found
        print(f"❌ No valid authentication for {self.path}")
        self.send_error(
            401, "Authentication required - Bearer token with service account required"
        )

    def validate_service_account_token(self, token):
        """Validate Google Service Account JWT token"""
        try:
            print(f"🔍 Validating token: {token[:20]}...")

            # Verify the token with Google's public keys
            # For simplicity, we'll use Google's tokeninfo endpoint
            response = requests.get(
                f"https://www.googleapis.com/oauth2/v1/tokeninfo?access_token={token}",
                timeout=5,
            )

            print(f"🌐 Google tokeninfo response status: {response.status_code}")

            if response.status_code == 200:
                token_info = response.json()
                print(f"📋 Token info: {token_info}")

                # Check if it's a service account
                if "email" in token_info and token_info.get("email", "").endswith(
                    ".iam.gserviceaccount.com"
                ):
                    print(f"✅ Valid service account: {token_info.get('email')}")
                    return True
                # Or check for valid scope
                if "scope" in token_info:
                    print(f"✅ Valid scope found: {token_info.get('scope')}")
                    return True

                print(
                    f"❌ Token validation failed - not a service account or missing scope"
                )
                print(f"   Email: {token_info.get('email', 'N/A')}")
                print(f"   Scope: {token_info.get('scope', 'N/A')}")

            else:
                print(f"❌ Google tokeninfo API returned {response.status_code}")
                print(f"   Response: {response.text}")

            return False

        except Exception as e:
            print(f"Token validation error: {e}")
            return False

    def proxy_to_jaeger(self):
        """Proxy the authenticated request to Jaeger"""
        try:
            # Read request body if present
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b""

            # Prepare headers for forwarding
            forward_headers = {}
            for key, value in self.headers.items():
                if key.lower() not in ["host", "content-length"]:
                    forward_headers[key] = value

            # Make request to Jaeger
            url = f"{JAEGER_OTEL_ENDPOINT}{self.path}"

            response = requests.request(
                method=self.command,
                url=url,
                headers=forward_headers,
                data=body,
                timeout=30,
            )

            # Send response back to client
            self.send_response(response.status_code)

            # Forward response headers
            for key, value in response.headers.items():
                if key.lower() not in ["content-encoding", "transfer-encoding"]:
                    self.send_header(key, value)

            self.end_headers()

            # Forward response body
            if response.content:
                self.wfile.write(response.content)

        except Exception as e:
            print(f"Proxy error: {e}")
            self.send_error(500, f"Proxy error: {str(e)}")


def run_server():
    """Run the authentication middleware server"""
    print(f"🚀 Starting authentication middleware on port {LISTEN_PORT}")
    print("   Supports Google Service Account JWT tokens")
    print("")

    server = HTTPServer(("0.0.0.0", LISTEN_PORT), AuthMiddleware)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Shutting down authentication middleware")
        server.shutdown()


if __name__ == "__main__":
    # Check dependencies
    try:
        import requests

        print("✅ Dependencies available")
    except ImportError:
        print("❌ Missing dependencies. Install with:")
        print("   pip install requests PyJWT")
        exit(1)

    run_server()
