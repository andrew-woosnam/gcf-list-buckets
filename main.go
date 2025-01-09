package gcf

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"

	"cloud.google.com/go/storage"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/googleapi"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	storagev1 "google.golang.org/api/storage/v1"
)

type GCloudFunctionConfig struct {
	StorageBucketName           string
	CloudFunctionServiceAccount string
	BillingProjectID            string
	StorageClientAudience       string
}

func NewGCloudFunctionConfig() *GCloudFunctionConfig {
	return &GCloudFunctionConfig{
		StorageBucketName:           os.Getenv("BUCKET_NAME"),
		CloudFunctionServiceAccount: os.Getenv("CLOUD_FUNCTION_SERVICE_ACCOUNT_NAME"),
		BillingProjectID:            os.Getenv("COMPUTE_PROJECT_ID"),
		StorageClientAudience:       "https://storage.googleapis.com",
	}
}

func createStorageClientWithOAuth(ctx context.Context, w http.ResponseWriter) (*storage.Client, error) {
	tokenSource, err := google.DefaultTokenSource(ctx, storagev1.CloudPlatformScope)
	if err != nil {
		return nil, fmt.Errorf("failed to create token source: %v", err)
	}

	// Generate and print the token
	token, err := tokenSource.Token()
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve token: %v", err)
	}

	// Print the token to the HTTP response
	fmt.Fprintf(w, "OAuth Token: %s\n", token.AccessToken)

	// Return the storage client
	return storage.NewClient(ctx, option.WithTokenSource(tokenSource))
}

func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	ctx := r.Context()
	cfg := NewGCloudFunctionConfig()

	fmt.Fprintf(w, "Bucket: %s, Billing Project: %s\n", cfg.StorageBucketName, cfg.BillingProjectID)

	client, err := createStorageClientWithOAuth(ctx, w)
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()

	bucket := client.Bucket(cfg.StorageBucketName).UserProject(cfg.BillingProjectID)
	fmt.Fprintf(w, "Verifying bucket existence...\n")
	if _, err := bucket.Attrs(ctx); err != nil {
		fmt.Fprintf(w, "Bucket verification error: %v\n", err)
		return
	}
	fmt.Fprintf(w, "Bucket exists. Listing objects...\n")

	it := bucket.Objects(ctx, nil)
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
}

func downloadObject(ctx context.Context, client *storage.Client, bucketName, objectName string, w http.ResponseWriter) error {
	rc, err := client.Bucket(bucketName).Object(objectName).NewReader(ctx)
	if err != nil {
		return fmt.Errorf("failed to create reader for object %s: %v", objectName, err)
	}
	defer rc.Close()

	localFile, err := os.Create(objectName)
	if err != nil {
		return fmt.Errorf("failed to create local file: %v", err)
	}
	defer localFile.Close()

	if _, err := io.Copy(localFile, rc); err != nil {
		return fmt.Errorf("failed to copy object data to local file: %v", err)
	}

	fmt.Fprintf(w, "Downloaded object %s to local file %s\n", objectName, objectName)
	return nil
}

func handleError(w http.ResponseWriter, err error) {
	if gErr, ok := err.(*googleapi.Error); ok {
		fmt.Fprintf(w, "Error Code: %d\nMessage: %s\n", gErr.Code, gErr.Message)
		for _, detail := range gErr.Errors {
			fmt.Fprintf(w, "Reason: %s, Message: %s\n", detail.Reason, detail.Message)
		}
	} else {
		fmt.Fprintf(w, "Unknown error: %v\n", err)
	}
}
