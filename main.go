package gcf

import (
	"context"
	"fmt"

	credentials "cloud.google.com/go/iam/credentials/apiv1"
	credentialspb "cloud.google.com/go/iam/credentials/apiv1/credentialspb"
	"cloud.google.com/go/storage"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

type Config struct {
	TargetBucket         string
	TargetServiceAccount string
}

func NewConfig() *Config {
	return &Config{
		TargetBucket:         "my-super-cool-bucket",
		TargetServiceAccount: "bucket-reader@striped-device-445917-b7.iam.gserviceaccount.com",
	}
}

// generates an access token for the target service account
func generateAccessToken(ctx context.Context, targetServiceAccount string) (string, error) {
	// Create an IAM Credentials client
	iamClient, err := credentials.NewIamCredentialsClient(ctx, option.WithScopes("https://www.googleapis.com/auth/cloud-platform"))
	if err != nil {
		return "", fmt.Errorf("failed to create IAM Credentials client: %v", err)
	}
	defer iamClient.Close()

	// Build the request
	req := &credentialspb.GenerateAccessTokenRequest{
		Name:  fmt.Sprintf("projects/-/serviceAccounts/%s", targetServiceAccount),
		Scope: []string{"https://www.googleapis.com/auth/cloud-platform"},
	}

	// Call the GenerateAccessToken method
	resp, err := iamClient.GenerateAccessToken(ctx, req)
	if err != nil {
		return "", fmt.Errorf("failed to generate access token: %v", err)
	}

	return resp.AccessToken, nil
}

// creates a storage client using the provided audience
func createStorageClient(ctx context.Context, audience string) (*storage.Client, error) {
	// Generate a token source for the specified audience
	tokenSource, err := idtoken.NewTokenSource(ctx, audience)
	if err != nil {
		return nil, fmt.Errorf("failed to create token source: %v", err)
	}

	// Create a storage client using the token source
	client, err := storage.NewClient(ctx, option.WithTokenSource(tokenSource))
	if err != nil {
		return nil, fmt.Errorf("failed to create storage client: %v", err)
	}
	return client, nil
}

// lists objects in the given GCS bucket
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

// handles HTTP requests and lists objects in a GCS bucket
func ListBucketObjects(ctx context.Context) {
	// Load the configuration
	cfg := NewConfig()

	// Hardcoded audience for GCS
	audience := "https://storage.googleapis.com"

	// Step 1: Create a storage client
	client, err := createStorageClient(ctx, audience)
	if err != nil {
		fmt.Printf("Error creating storage client: %v\n", err)
		return
	}
	defer client.Close()

	// Step 2: List objects in the target bucket
	objects, err := listObjectsInBucket(ctx, client, cfg.TargetBucket)
	if err != nil {
		fmt.Printf("Error listing objects in bucket: %v\n", err)
		return
	}

	// Step 3: Print the objects
	fmt.Println("Objects in bucket:")
	for _, obj := range objects {
		fmt.Println(obj)
	}
}

func main() {
	ctx := context.Background()
	ListBucketObjects(ctx)
}
