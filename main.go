package gcf

import (
	"context"
	"fmt"
	"net/http"
	"os"

	"cloud.google.com/go/storage"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/googleapi"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	storagev1 "google.golang.org/api/storage/v1"
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
		StorageBucketName:           os.Getenv("STORAGE_BUCKET"),
		CloudFunctionServiceAccount: os.Getenv("CLOUD_FUNC_SA"),
		BillingProjectID:            os.Getenv("BILLING_PROJECT"),
		StorageClientAudience:       "https://storage.googleapis.com",
	}
}

func createStorageClientWithOAuth(ctx context.Context) (*storage.Client, error) {
	// Use the default service account's token source with the required scope.
	tokenSource, err := google.DefaultTokenSource(ctx, storagev1.CloudPlatformScope)
	if err != nil {
		return nil, fmt.Errorf("Failed to create token source: %v", err)
	}

	// Create a Storage client with the OAuth token source.
	client, err := storage.NewClient(ctx, option.WithTokenSource(tokenSource))
	if err != nil {
		return nil, fmt.Errorf("Failed to create storage client: %v", err)
	}

	return client, nil
}

// createStorageClient initializes a Cloud Storage client with the provided audience
func createStorageClient(ctx context.Context, audience string, w http.ResponseWriter) (*storage.Client, error) {
	tokenSource, err := idtoken.NewTokenSource(ctx, audience)
	if err != nil {
		fmt.Fprintf(w, "Failed to create token source: %v\n", err)
		return nil, err
	}

	token, err := tokenSource.Token()
	if err != nil {
		fmt.Fprintf(w, "Failed to retrieve token: %v\n", err)
		return nil, err
	}
	fmt.Fprintf(w, "Access Token: %s\n", token.AccessToken)

	client, err := storage.NewClient(ctx, option.WithTokenSource(tokenSource))
	if err != nil {
		fmt.Fprintf(w, "Failed to create storage client: %v\n", err)
		return nil, err
	}
	return client, nil
}

// checkBucketAccess verifies permissions by attempting to access bucket metadata
func checkBucketAccess(ctx context.Context, client *storage.Client, bucketName, userProject string, w http.ResponseWriter) error {
	bucket := client.Bucket(bucketName).UserProject(userProject)

	attrs, err := bucket.Attrs(ctx)
	if err != nil {
		handleError(w, err)
		return err
	}

	fmt.Fprintf(w, "Bucket Name: %s\n", attrs.Name)
	fmt.Fprintf(w, "Bucket Location: %s\n", attrs.Location)
	fmt.Fprintf(w, "Requester Pays: %t\n", attrs.RequesterPays)
	return nil
}

// ListBucketObjects is the entry point for the Cloud Function
func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	ctx := r.Context()
	cfg := NewGCloudFunctionConfig()

	fmt.Fprintln(w, "Debug Information:")
	fmt.Fprintf(w, "Target Storage Bucket: %s\n", cfg.StorageBucketName)
	fmt.Fprintf(w, "Cloud Function Service Account: %s\n", cfg.CloudFunctionServiceAccount)
	fmt.Fprintf(w, "Billing Project ID: %s\n", cfg.BillingProjectID)
	fmt.Fprintln(w, "---")

	// Create the Storage Client using OAuth
	fmt.Fprintln(w, "Creating Storage Client with OAuth...")
	client, err := createStorageClientWithOAuth(ctx)
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()
	fmt.Fprintln(w, "Storage Client created successfully.")
	fmt.Fprintln(w, "---")

	// Check if the target bucket is accessible
	fmt.Fprintln(w, "Checking access to the target bucket...")
	err = checkBucketAccess(ctx, client, cfg.StorageBucketName, cfg.BillingProjectID, w)
	if err != nil {
		fmt.Fprintf(w, "Error accessing target bucket: %v\n", err)
		return
	}
	fmt.Fprintln(w, "---")

	// List objects in the target bucket
	fmt.Fprintln(w, "Listing objects in the target bucket...")
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

func handleError(w http.ResponseWriter, err error) {
	if gErr, ok := err.(*googleapi.Error); ok {
		fmt.Fprintf(w, "Error Code: %d\n", gErr.Code)
		fmt.Fprintf(w, "Error Message: %s\n", gErr.Message)
		fmt.Fprintf(w, "Error Body: %s\n", gErr.Body)
		for _, detail := range gErr.Errors {
			fmt.Fprintf(w, "Reason: %s, Message: %s\n", detail.Reason, detail.Message)
		}
	} else {
		// Generic error fallback
		fmt.Fprintf(w, "Unknown error: %v\n", err)
	}
}
