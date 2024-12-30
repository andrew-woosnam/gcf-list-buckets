package gcf

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"cloud.google.com/go/storage"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/option"
)

// GCloudFunctionConfig stores configuration for a Google Cloud Function
type GCloudFunctionConfig struct {
	StorageBucketName           string // Target GCS bucket
	CloudFunctionServiceAccount string // Cloud Function service account
	BillingProjectID            string // Billing project ID for Requester Pays
	StorageClientAudience       string // Audience for creating the Storage Client
}

// NewGCloudFunctionConfig initializes and returns a GCloudFunctionConfig object
func NewGCloudFunctionConfig() *GCloudFunctionConfig {
	return &GCloudFunctionConfig{
		StorageBucketName:           "tickleface-gcs",
		CloudFunctionServiceAccount: "576375071060-compute@developer.gserviceaccount.com",
		BillingProjectID:            "proj-awoosnam",
		StorageClientAudience:       "https://storage.googleapis.com",
	}
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
	// Create an OIDC token source for the specified audience
	tokenSource, err := idtoken.NewTokenSource(ctx, audience)
	if err != nil {
		return nil, fmt.Errorf("failed to create token source: %v", err)
	}

	// Use the token source to create a Storage client
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

	// Step 1: Create Storage Client using OIDC Token
	fmt.Fprintln(w, "Step 1: Creating Storage Client with OIDC Token...")
	client, err := createStorageClient(ctx, cfg.StorageClientAudience)
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()
	fmt.Fprintln(w, "Storage Client created successfully.")
	fmt.Fprintln(w, "---")

	// Step 2: List objects in the bucket
	fmt.Fprintln(w, "Step 2: Listing bucket objects...")
	it := client.Bucket(cfg.StorageBucketName).Objects(ctx, nil)
	for {
		objAttrs, err := it.Next()
		if err != nil {
			if err.Error() == "iterator.Done" {
				break
			}
			fmt.Fprintf(w, "Error listing objects: %v\n", err)
			return
		}
		fmt.Fprintf(w, "Object: %s\n", objAttrs.Name)
	}
}
