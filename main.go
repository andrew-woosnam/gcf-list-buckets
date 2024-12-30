package gcf

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	credentials "cloud.google.com/go/iam/credentials/apiv1"
	credentialspb "cloud.google.com/go/iam/credentials/apiv1/credentialspb"
	"cloud.google.com/go/storage"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/option"
)

// GCloudFunctionConfig stores configuration for a Google Cloud Function
type GCloudFunctionConfig struct {
	StorageBucketName           string   // Target GCS bucket
	CloudFunctionServiceAccount string   // Cloud Function service account
	BillingProjectID            string   // Billing project ID for Requester Pays
	AccessTokenScope            []string // OAuth Scopes
	StorageClientAudience       string   // Audience for creating the Storage Client
	IAMClientScopes             []string // Scopes for IAM Credentials Client
}

// NewGCloudFunctionConfig initializes and returns a GCloudFunctionConfig object
func NewGCloudFunctionConfig() *GCloudFunctionConfig {
	return &GCloudFunctionConfig{
		StorageBucketName:           "tickleface-gcs",
		CloudFunctionServiceAccount: "576375071060-compute@developer.gserviceaccount.com",
		BillingProjectID:            "proj-awoosnam",
		AccessTokenScope:            []string{"https://www.googleapis.com/auth/devstorage.read_only"},
		StorageClientAudience:       "https://storage.googleapis.com",
		IAMClientScopes:             []string{"https://www.googleapis.com/auth/cloud-platform"},
	}
}

// generateAccessToken generates a short-lived access token for the specified service account
func generateAccessToken(ctx context.Context, serviceAccount string, scopes []string) (string, error) {
	iamClient, err := credentials.NewIamCredentialsClient(ctx, option.WithScopes(scopes...))
	if err != nil {
		return "", fmt.Errorf("failed to create IAM Credentials client: %v", err)
	}
	defer iamClient.Close()

	req := &credentialspb.GenerateAccessTokenRequest{
		Name:  fmt.Sprintf("projects/-/serviceAccounts/%s", serviceAccount),
		Scope: scopes,
	}

	resp, err := iamClient.GenerateAccessToken(ctx, req)
	if err != nil {
		return "", fmt.Errorf("failed to generate access token: %v", err)
	}

	return resp.AccessToken, nil
}

// decodeToken decodes and returns the payload of a JWT token
func decodeToken(token string) (map[string]interface{}, error) {
	parts := splitToken(token)
	if len(parts) != 3 {
		return nil, fmt.Errorf("invalid JWT format: expected 3 parts but got %d", len(parts))
	}

	// Decode the payload (middle part of the JWT)
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("failed to decode token payload: %v", err)
	}

	// Unmarshal the payload into a map
	var result map[string]interface{}
	if err := json.Unmarshal(payload, &result); err != nil {
		return nil, fmt.Errorf("failed to parse token payload: %v", err)
	}

	return result, nil
}

// splitToken splits a JWT token into its parts (header, payload, signature)
func splitToken(token string) []string {
	return strings.Split(token, ".")
}

// createStorageClient initializes a Cloud Storage client with the provided audience
func createStorageClient(ctx context.Context, audience string) (*storage.Client, error) {
	tokenSource, err := idtoken.NewTokenSource(ctx, audience)
	if err != nil {
		return nil, fmt.Errorf("failed to create token source: %v", err)
	}

	client, err := storage.NewClient(ctx, option.WithTokenSource(tokenSource))
	if err != nil {
		return nil, fmt.Errorf("failed to create storage client: %v", err)
	}
	return client, nil
}

func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	ctx := r.Context()
	cfg := NewGCloudFunctionConfig()

	// Debug Information
	fmt.Fprintln(w, "Debug Information:")
	fmt.Fprintf(w, "Storage Bucket: %s\n", cfg.StorageBucketName)
	fmt.Fprintf(w, "Cloud Function Service Account: %s\n", cfg.CloudFunctionServiceAccount)
	fmt.Fprintf(w, "Billing Project ID: %s\n", cfg.BillingProjectID)
	fmt.Fprintln(w, "---")

	// Step 1: Generate Access Token
	fmt.Fprintln(w, "Step 1: Generating Access Token...")
	accessToken, err := generateAccessToken(ctx, cfg.CloudFunctionServiceAccount, cfg.IAMClientScopes)
	if err != nil {
		fmt.Fprintf(w, "Error generating access token: %v\n", err)
		return
	}
	fmt.Fprintln(w, "Access Token generated successfully.")
	fmt.Fprintf(w, "Access Token: %s\n", accessToken)

	// Decode and print the token payload
	fmt.Fprintln(w, "Decoded Access Token Payload:")
	tokenPayload, err := decodeToken(accessToken)
	if err != nil {
		fmt.Fprintf(w, "Error decoding token payload: %v\n", err)
		return
	}
	for key, value := range tokenPayload {
		fmt.Fprintf(w, "%s: %v\n", key, value)
	}
	fmt.Fprintln(w, "---")

	// Step 2: Create Storage Client
	fmt.Fprintln(w, "Step 2: Creating Storage Client...")
	client, err := createStorageClient(ctx, cfg.StorageClientAudience)
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()
	fmt.Fprintln(w, "Storage Client created successfully.")
	fmt.Fprintln(w, "---")
}
