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

// Config stores the configuration for the GCF
type Config struct {
	TargetBucket         string
	TargetServiceAccount string
}

// NewConfig initializes the configuration
func NewConfig() *Config {
	return &Config{
		TargetBucket:         "tickleface-gcs",
		TargetServiceAccount: "576375071060-compute@developer.gserviceaccount.com",
	}
}

// generateAccessToken generates an access token for the target service account
func generateAccessToken(ctx context.Context, targetServiceAccount string) (string, error) {
	iamClient, err := credentials.NewIamCredentialsClient(ctx, option.WithScopes("https://www.googleapis.com/auth/cloud-platform"))
	if err != nil {
		return "", fmt.Errorf("failed to create IAM Credentials client: %v", err)
	}
	defer iamClient.Close()

	req := &credentialspb.GenerateAccessTokenRequest{
		Name:  fmt.Sprintf("projects/-/serviceAccounts/%s", targetServiceAccount),
		Scope: []string{"https://www.googleapis.com/auth/cloud-platform"},
	}

	resp, err := iamClient.GenerateAccessToken(ctx, req)
	if err != nil {
		return "", fmt.Errorf("failed to generate access token: %v", err)
	}

	return resp.AccessToken, nil
}

// createStorageClient creates a storage client using the provided audience
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

// listObjectsInBucket lists objects in the given GCS bucket
func listObjectsInBucket(ctx context.Context, client *storage.Client, bucketName string) ([]string, error) {
	bucket := client.Bucket(bucketName)
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

func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	// Collect environment variables
	envVars := os.Environ()

	// Write the environment variables to the response
	w.Header().Set("Content-Type", "text/plain")
	fmt.Fprintln(w, "Environment Variables:")
	for _, env := range envVars {
		fmt.Fprintln(w, env)
	}
	fmt.Fprintln(w, "---")

	// Proceed with the rest of the logic
	ctx := r.Context()
	cfg := NewConfig()
	audience := "https://storage.googleapis.com"

	client, err := createStorageClient(ctx, audience)
	if err != nil {
		fmt.Fprintf(w, "Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()

	objects, err := listObjectsInBucket(ctx, client, cfg.TargetBucket)
	if err != nil {
		fmt.Fprintf(w, "Error listing objects in bucket: %v\n", err)
		return
	}

	// Write the objects in the bucket to the response
	fmt.Fprintln(w, "Objects in bucket:")
	for _, obj := range objects {
		fmt.Fprintln(w, obj)
	}
}
