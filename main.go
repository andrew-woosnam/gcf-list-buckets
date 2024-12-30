package gcf

import (
	"context"
	"fmt"
	"net/http"
	"os"

	credentials "cloud.google.com/go/iam/credentials/apiv1"
	credentialspb "cloud.google.com/go/iam/credentials/apiv1/credentialspb"
	"cloud.google.com/go/storage"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

// Configuration and Initialization Section
// ----------------------------------------

// Config stores the configuration for the GCF
type Config struct {
	StorageBucketName           string // Target GCS bucket
	CloudFunctionServiceAccount string // Service account assigned to the Cloud Function
	BillingProjectID            string // Project used for Requester Pays billing
}

// NewConfig initializes and returns a Config object
func NewConfig() *Config {
	return &Config{
		StorageBucketName:           "tickleface-gcs",
		CloudFunctionServiceAccount: "576375071060-compute@developer.gserviceaccount.com",
		BillingProjectID:            "proj-awoosnam",
	}
}

// Token and Client Utilities
// --------------------------

// generateAccessToken generates a short-lived access token for the specified service account
func generateAccessToken(ctx context.Context, serviceAccount string) (string, error) {
	iamClient, err := credentials.NewIamCredentialsClient(
		ctx, option.WithScopes("https://www.googleapis.com/auth/cloud-platform"))
	if err != nil {
		return "", fmt.Errorf("failed to create IAM Credentials client: %v", err)
	}
	defer iamClient.Close()

	req := &credentialspb.GenerateAccessTokenRequest{
		Name:  fmt.Sprintf("projects/-/serviceAccounts/%s", serviceAccount),
		Scope: []string{"https://www.googleapis.com/auth/devstorage.read_only"}, // Explicit scope for Cloud Storage
	}

	resp, err := iamClient.GenerateAccessToken(ctx, req)
	if err != nil {
		return "", fmt.Errorf("failed to generate access token: %v", err)
	}

	return resp.AccessToken, nil
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

// Storage Operations
// -------------------

// checkBucketAccess attempts to list objects in the bucket to verify permissions
func checkBucketAccess(ctx context.Context, client *storage.Client, bucketName string) error {
	bucket := client.Bucket(bucketName)
	it := bucket.Objects(ctx, nil)

	_, err := it.Next()
	if err == iterator.Done {
		// Bucket is accessible but empty
		return nil
	}
	if err != nil {
		return fmt.Errorf("failed to access bucket '%s': %v", bucketName, err)
	}
	return nil
}

// listObjectsInBucket retrieves and returns the names of all objects in the bucket
func listObjectsInBucket(ctx context.Context, client *storage.Client, bucketName, billingProjectID string) ([]string, error) {
	bucket := client.Bucket(bucketName).UserProject(billingProjectID)
	it := bucket.Objects(ctx, nil)

	var objects []string
	for {
		objAttrs, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error listing objects: %v", err)
		}
		objects = append(objects, objAttrs.Name)
	}
	return objects, nil
}

// HTTP Handler
// ------------

// ListBucketObjects is the main HTTP handler for the Cloud Function
func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	ctx := r.Context()
	cfg := NewConfig()

	// Step 1: Display Debug Information
	fmt.Fprintln(w, "Debug Information:")
	fmt.Fprintf(w, "Target Storage Bucket: %s\n", cfg.StorageBucketName)
	fmt.Fprintf(w, "Cloud Function Service Account: %s\n", cfg.CloudFunctionServiceAccount)
	fmt.Fprintf(w, "Billing Project ID: %s\n", cfg.BillingProjectID)
	fmt.Fprintln(w, "---")

	// Step 2: Generate Access Token
	fmt.Fprintln(w, "Step 1: Generating Access Token...")
	accessToken, err := generateAccessToken(ctx, cfg.CloudFunctionServiceAccount)
	if err != nil {
		fmt.Fprintf(w, "Error generating access token: %v\n", err)
		return
	}
	fmt.Fprintln(w, "Access Token generated successfully.")
	fmt.Fprintf(w, "Access Token (last 10 characters): ...%s\n", accessToken[len(accessToken)-10:])
	fmt.Fprintln(w, "---")

	// Step 3: Create Storage Client
	fmt.Fprintln(w, "Step 2: Creating Storage Client...")
	client, err := createStorageClient(ctx, "https://storage.googleapis.com")
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()
	fmt.Fprintln(w, "Storage Client created successfully.")
	fmt.Fprintln(w, "---")

	// Step 4: Check Bucket Permissions
	fmt.Fprintln(w, "Step 3: Checking Bucket Permissions...")
	err = checkBucketAccess(ctx, client, cfg.StorageBucketName)
	if err != nil {
		fmt.Fprintf(w, "Bucket access check failed: %v\n", err)
		return
	}
	fmt.Fprintln(w, "Bucket access verified successfully.")
	fmt.Fprintln(w, "---")

	// Step 5: List Objects in Bucket
	fmt.Fprintln(w, "Step 4: Listing Objects in Bucket...")
	objects, err := listObjectsInBucket(ctx, client, cfg.StorageBucketName, cfg.BillingProjectID)
	if err != nil {
		fmt.Fprintf(w, "Error listing objects in bucket: %v\n", err)
		return
	}
	fmt.Fprintln(w, "Objects in bucket retrieved successfully:")
	for _, obj := range objects {
		fmt.Fprintln(w, obj)
	}
	fmt.Fprintln(w, "---")

	// Step 6: Print Environment Variables (Optional)
	fmt.Fprintln(w, "Step 5: Environment Variables:")
	envVars := os.Environ()
	for _, env := range envVars {
		fmt.Fprintln(w, env)
	}
}
