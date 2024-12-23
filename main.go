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
func debugLog(w http.ResponseWriter, format string, args ...interface{}) {
	if os.Getenv("DEBUG") == "true" {
		fmt.Fprintf(w, format, args...)
	}
}

type GCloudFunctionConfig struct {
	BucketName            string
	ComputeProjectId      string
	StorageClientAudience string
}

func NewGCloudFunctionConfig() *GCloudFunctionConfig {
	return &GCloudFunctionConfig{
		BucketName:            os.Getenv("BUCKET_NAME"),
		ComputeProjectId:      os.Getenv("COMPUTE_PROJECT_ID"),
		StorageClientAudience: "https://storage.googleapis.com",
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
	debugLog(w, "Checking bucket access for bucket %s with user project %s\n", bucketName, userProject)
	bucket := client.Bucket(bucketName).UserProject(userProject)

	// Validate bucket attributes
	attrs, err := bucket.Attrs(ctx)
	if err != nil {
		handleError(w, err)
		return fmt.Errorf("error fetching bucket attributes: %w", err)
	}
	fmt.Fprintf(w, "Bucket Name: %s\nBucket Location: %s\nRequester Pays: %t\n", attrs.Name, attrs.Location, attrs.RequesterPays)

	debugLog(w, "Bucket access verified successfully for bucket %s with user project %s.\n", bucketName, userProject)
	return nil
}

func printEnv(w http.ResponseWriter) {
	envVars := os.Environ()

	debugLog(w, "Environment Variables:\n")
	debugLog(w, "+---------------------\n")
	for _, envVar := range envVars {
		debugLog(w, "| %s\n", envVar)
	}
	debugLog(w, "+---------------------\n")
}

func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	ctx := r.Context()

	printEnv(w)

	cfg := NewGCloudFunctionConfig()

	debugLog(w, "Configuration loaded: Bucket=%s, ComputeProjectId=%s\n", cfg.BucketName, cfg.ComputeProjectId)

	client, err := createStorageClientWithOAuth(ctx)
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()
	debugLog(w, "Storage client created successfully.\n")

	if err := checkBucketAccess(ctx, client, cfg.BucketName, cfg.ComputeProjectId, w); err != nil {
		fmt.Fprintf(w, "Error checking bucket access: %v\n", err)
		return
	}

	it := client.Bucket(cfg.BucketName).UserProject(cfg.ComputeProjectId).Objects(ctx, nil)

	debugLog(w, "Listing objects in bucket %s...\n", cfg.BucketName)
	var firstObjectName string
	for {
		objAttrs, err := it.Next()
		if err == iterator.Done {
			debugLog(w, "Reached end of object list.\n")
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
		debugLog(w, "No objects found in the bucket.\n")
		return
	}

	debugLog(w, "Preparing to download first object: %s\n", firstObjectName)
	if err := downloadObject(ctx, client, cfg.BucketName, firstObjectName, w); err != nil {
		fmt.Fprintf(w, "Error downloading object: %v\n", err)
		return
	}
	debugLog(w, "Successfully downloaded object: %s\n", firstObjectName)
}

func downloadObject(ctx context.Context, client *storage.Client, bucketName, objectName string, w http.ResponseWriter) error {
	debugLog(w, "Starting download for object %s in bucket %s\n", objectName, bucketName)
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
	debugLog(w, "Successfully downloaded object %s\n", objectName)
	return nil
}

func handleError(w http.ResponseWriter, err error) {
	if gErr, ok := err.(*googleapi.Error); ok {
		fmt.Fprintf(w, "Error Code: %d\nMessage: %s\nDetails:\n", gErr.Code, gErr.Message)
		debugLog(w, "Full Error: %+v\n", gErr)

		for _, detail := range gErr.Errors {
			fmt.Fprintf(w, "Reason: %s, Message: %s\n", detail.Reason, detail.Message)
		}
	} else {
		fmt.Fprintf(w, "Unknown error: %v\n", err)
		debugLog(w, "Unknown error: %+v\n", err)
	}
}
