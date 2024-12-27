package gcf

import (
	"context"
	"fmt"
)

func main() {}

// ListBucketObjects handles HTTP requests and lists objects in a GCS bucket
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
