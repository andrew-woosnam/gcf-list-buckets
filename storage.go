package gcf

import (
	"context"
	"fmt"

	"cloud.google.com/go/storage"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

// createStorageClient creates a storage client using the provided access token
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
