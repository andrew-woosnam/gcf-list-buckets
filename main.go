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

// Debug logger function
func debugLog(format string, args ...interface{}) {
	if os.Getenv("DEBUG") == "true" {
		fmt.Printf(format, args...)
	}
}

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

func createStorageClientWithOAuth(ctx context.Context) (*storage.Client, error) {
	tokenSource, err := google.DefaultTokenSource(ctx, storagev1.CloudPlatformScope)
	if err != nil {
		return nil, fmt.Errorf("failed to create token source: %v", err)
	}
	return storage.NewClient(ctx, option.WithTokenSource(tokenSource))
}

func checkBucketAccess(ctx context.Context, client *storage.Client, bucketName, userProject string, w http.ResponseWriter) error {
	debugLog("Debug: Checking bucket access for bucket %s with user project %s\n", bucketName, userProject)
	bucket := client.Bucket(bucketName).UserProject(userProject)
	attrs, err := bucket.Attrs(ctx)
	if err != nil {
		handleError(w, err)
		return err
	}
	fmt.Fprintf(w, "Bucket Name: %s\nBucket Location: %s\nRequester Pays: %t\n", attrs.Name, attrs.Location, attrs.RequesterPays)
	debugLog("Debug: Bucket access verified for bucket %s\n", bucketName)
	return nil
}

func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	ctx := r.Context()
	cfg := NewGCloudFunctionConfig()

	debugLog("Debug: Configuration loaded: Bucket=%s, BillingProjectID=%s\n", cfg.StorageBucketName, cfg.BillingProjectID)

	client, err := createStorageClientWithOAuth(ctx)
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()
	debugLog("Debug: Storage client created successfully.\n")

	if err := checkBucketAccess(ctx, client, cfg.StorageBucketName, cfg.BillingProjectID, w); err != nil {
		fmt.Fprintf(w, "Error checking bucket access: %v\n", err)
		return
	}

	it := client.Bucket(cfg.StorageBucketName).UserProject(cfg.BillingProjectID).Objects(ctx, nil)

	debugLog("Debug: Listing objects in bucket %s...\n", cfg.StorageBucketName)
	var firstObjectName string
	for {
		objAttrs, err := it.Next()
		if err == iterator.Done {
			debugLog("Debug: Reached end of object list.\n")
			break
		}
		if err != nil {
			fmt.Fprintf(w, "Error listing objects: %v\n", err)
			return
		}
		fmt.Fprintf(w, "Object: %s\n", objAttrs.Name)
		if firstObjectName == "" {
			firstObjectName = objAttrs.Name
		}
	}

	if firstObjectName == "" {
		fmt.Fprintln(w, "No objects found in the bucket.")
		debugLog("Debug: No objects found in the bucket.\n")
		return
	}

	debugLog("Debug: Preparing to download first object: %s\n", firstObjectName)
	if err := downloadObject(ctx, client, cfg.StorageBucketName, firstObjectName, w); err != nil {
		fmt.Fprintf(w, "Error downloading object: %v\n", err)
		return
	}
	debugLog("Debug: Successfully downloaded object: %s\n", firstObjectName)
}

func downloadObject(ctx context.Context, client *storage.Client, bucketName, objectName string, w http.ResponseWriter) error {
	debugLog("Debug: Starting download for object %s in bucket %s\n", objectName, bucketName)
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
	debugLog("Debug: Successfully downloaded object %s\n", objectName)
	return nil
}

func handleError(w http.ResponseWriter, err error) {
	if gErr, ok := err.(*googleapi.Error); ok {
		fmt.Fprintf(w, "Error Code: %d\nMessage: %s\nDetails:\n", gErr.Code, gErr.Message)
		debugLog("Debug: Full Error: %+v\n", gErr)

		for _, detail := range gErr.Errors {
			fmt.Fprintf(w, "Reason: %s, Message: %s\n", detail.Reason, detail.Message)
		}
	} else {
		fmt.Fprintf(w, "Unknown error: %v\n", err)
		debugLog("Debug: Unknown error: %+v\n", err)
	}
}
