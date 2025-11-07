package main

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
)

// ServiceAccountKey represents the Google Cloud service account JSON structure
type ServiceAccountKey struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
}

// generateIAPJWT creates a JWT for Google IAP authentication using RS256
func generateIAPJWT(serviceAccountKeyPath, audience string) (string, error) {
	// Read service account key file
	keyData, err := os.ReadFile(serviceAccountKeyPath)
	if err != nil {
		return "", fmt.Errorf("failed to read service account key: %w", err)
	}

	var saKey ServiceAccountKey
	if err := json.Unmarshal(keyData, &saKey); err != nil {
		return "", fmt.Errorf("failed to parse service account key: %w", err)
	}

	// Parse private key
	block, _ := pem.Decode([]byte(saKey.PrivateKey))
	if block == nil {
		return "", fmt.Errorf("failed to decode PEM block")
	}

	privateKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return "", fmt.Errorf("failed to parse private key: %w", err)
	}

	rsaKey, ok := privateKey.(*rsa.PrivateKey)
	if !ok {
		return "", fmt.Errorf("private key is not RSA")
	}

	// Create JWT claims with aud as a string (not array)
	now := time.Now()
	claims := jwt.MapClaims{
		"iss": saKey.ClientEmail,
		"sub": saKey.ClientEmail,
		"aud": audience,
		"iat": now.Unix(),
		"exp": now.Add(1 * time.Hour).Unix(),
	}

	// Create and sign the token
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tokenString, err := token.SignedString(rsaKey)
	if err != nil {
		return "", fmt.Errorf("failed to sign JWT: %w", err)
	}

	return tokenString, nil
}

func main() {
	// Configuration
	serviceAccountKeyPath := "/home/lance/Downloads/tigera-dev-tools-24b915217988.json"
	otlpEndpoint := "banzai-otel.dev-tools.tigera.net"
	otlpEndpointURL := "https://" + otlpEndpoint
	serviceName := "otel-go-test-service"

	// Generate IAP JWT
	fmt.Println("Generating IAP JWT...")
	iapJWT, err := generateIAPJWT(serviceAccountKeyPath, otlpEndpointURL+"/*")
	if err != nil {
		log.Fatalf("Failed to generate IAP JWT: %v", err)
	}
	fmt.Println("✓ Generated IAP JWT")

	// Create OTLP HTTP exporter with IAP authentication
	ctx := context.Background()
	exporter, err := otlptracehttp.New(
		ctx,
		otlptracehttp.WithEndpoint(otlpEndpoint),
		otlptracehttp.WithHeaders(map[string]string{
			"Authorization": "Bearer " + iapJWT,
		}),
	)
	if err != nil {
		log.Fatalf("Failed to create OTLP exporter: %v", err)
	}
	defer exporter.Shutdown(ctx)

	// Create resource with service information
	res, err := resource.New(
		ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion("1.0.0"),
			attribute.String("environment", "dev"),
		),
	)
	if err != nil {
		log.Fatalf("Failed to create resource: %v", err)
	}

	// Create tracer provider
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	defer func() {
		if err := tp.Shutdown(ctx); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	otel.SetTracerProvider(tp)

	// Create tracer
	tracer := tp.Tracer("example-tracer")

	// Create and send a simple span
	fmt.Println("Sending span via OpenTelemetry Go SDK...")
	_, span := tracer.Start(ctx, "test-operation-from-go",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("test.attribute", "example-value"),
			attribute.String("environment", "dev"),
		),
	)

	// Simulate some work
	time.Sleep(100 * time.Millisecond)

	span.End()

	// Ensure all spans are exported before exiting
	if err := tp.ForceFlush(ctx); err != nil {
		log.Printf("Error flushing spans: %v", err)
	}

	fmt.Println("✅ Span sent successfully!")
	fmt.Printf("🔍 Check Jaeger UI: https://jaeger.dev-tools.tigera.net/search?service=%s&lookback=1h\n", serviceName)
}
