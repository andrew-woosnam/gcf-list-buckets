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
	"google.golang.org/api/iterator"
	"google.golang.org/api/oauth2/v2"
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
	parts := strings.Split(token, ".")
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

// createStorageClient initializes a Cloud Storage client with the provided audience
func createStorageClient(ctx context.Context, audience string, w http.ResponseWriter) (*storage.Client, error) {
	tokenSource, err := idtoken.NewTokenSource(ctx, audience)
	if err != nil {
		fmt.Fprintf(w, "Failed to create token source: %v\n", err)
		return nil, fmt.Errorf("failed to create token source: %v", err)
	}

	// Retrieve and log the token
	token, err := tokenSource.Token()
	if err != nil {
		fmt.Fprintf(w, "Failed to retrieve token: %v\n", err)
		return nil, fmt.Errorf("failed to retrieve token: %v", err)
	}
	fmt.Fprintf(w, "Access Token: %s\n", token.AccessToken)

	claims, err := decodeToken(token.AccessToken)
	if err != nil {
		fmt.Fprintf(w, "Failed to decode token claims: %v\n", err)
		return nil, fmt.Errorf("failed to decode token claims: %v", err)
	}
	fmt.Fprintf(w, "Token Claims: %+v\n", claims)

	// Create OAuth2 token source for scoped credentials
	oauth2TokenSource := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token.AccessToken})
	client, err := storage.NewClient(ctx, option.WithTokenSource(oauth2TokenSource))
	if err != nil {
		fmt.Fprintf(w, "Failed to create storage client: %v\n", err)
		return nil, fmt.Errorf("failed to create storage client: %v", err)
	}
	return client, nil
}

// checkBucketAccess verifies permissions by attempting to access bucket metadata
func checkBucketAccess(ctx context.Context, client *storage.Client, bucketName string, w http.ResponseWriter) error {
	bucket := client.Bucket(bucketName)

	// Attempt to fetch bucket metadata to verify access
	attrs, err := bucket.Attrs(ctx)
	if err != nil {
		fmt.Fprintf(w, "Failed to access bucket metadata: %v\n", err)
		return fmt.Errorf("failed to access bucket '%s': %v", bucketName, err)
	}

	// Log bucket details for debugging
	fmt.Fprintf(w, "Bucket Name: %s\n", attrs.Name)
	fmt.Fprintf(w, "Bucket Location: %s\n", attrs.Location)
	fmt.Fprintf(w, "Requester Pays: %t\n", attrs.RequesterPays)
	return nil
}

func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	ctx := r.Context()
	cfg := NewGCloudFunctionConfig()

	fmt.Fprintln(w, "Debug Information:")
	fmt.Fprintf(w, "Storage Bucket: %s\n", cfg.StorageBucketName)
	fmt.Fprintf(w, "Cloud Function Service Account: %s\n", cfg.CloudFunctionServiceAccount)
	fmt.Fprintf(w, "Billing Project ID: %s\n", cfg.BillingProjectID)
	fmt.Fprintln(w, "---")

	// Step 1: Create Storage Client
	fmt.Fprintln(w, "Creating Storage Client...")
	client, err := createStorageClient(ctx, cfg.StorageClientAudience, w)
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()
	fmt.Fprintln(w, "Storage Client created successfully.")
	fmt.Fprintln(w, "---")

	// Step 2: Check Bucket Access
	fmt.Fprintln(w, "Checking bucket access...")
	err = checkBucketAccess(ctx, client, cfg.StorageBucketName, w)
	if err != nil {
		fmt.Fprintf(w, "Bucket access check failed: %v\n", err)
		return
	}
	fmt.Fprintln(w, "Bucket access verified successfully.")
	fmt.Fprintln(w, "---")

	// Step 3: List Objects in the Bucket
	fmt.Fprintln(w, "Listing bucket objects...")
	it := client.Bucket(cfg.StorageBucketName).UserProject(cfg.BillingProjectID).Objects(ctx, nil)
	for {
		objAttrs, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			fmt.Fprintf(w, "Error listing objects: %v\n", err)
			return
		}
		fmt.Fprintf(w, "Object: %s\n", objAttrs.Name)
	}
	fmt.Fprintln(w, "---")
}
