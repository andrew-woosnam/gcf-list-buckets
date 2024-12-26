package gcf

import (
	"context"
	"fmt"
	"net/http"

	"cloud.google.com/go/storage"
	"golang.org/x/oauth2"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

// createStorageClient creates a new storage client with the given access token
func createStorageClient(ctx context.Context, accessToken string) (*storage.Client, error) {
	tokenSource := oauth2.StaticTokenSource(&oauth2.Token{
		AccessToken: accessToken,
		TokenType:   "Bearer",
	})
	return storage.NewClient(ctx, option.WithTokenSource(tokenSource))
}

// listBucketObjects lists objects in the specified GCS bucket
func listBucketObjects(ctx context.Context, client *storage.Client, bucketName string, w http.ResponseWriter) error {
	bucket := client.Bucket(bucketName)
	it := bucket.Objects(ctx, nil)
	fmt.Fprintf(w, "Objects in bucket %s:\n", bucketName)
	for {
		objAttr, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		fmt.Fprintf(w, " - %s\n", objAttr.Name)
	}
	return nil
}
