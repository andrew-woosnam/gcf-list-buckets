package gcf

import (
	"context"
	"fmt"
	"net/http"
)

// ListBucketObjects is the entry point for the Cloud Function
func ListBucketObjects(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()
	cfg := NewConfig()

	// Step 1: Create the credentials client
	credentialsClient, err := createCredentialsClient(ctx)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create credentials client: %v", err), http.StatusInternalServerError)
		return
	}
	defer credentialsClient.Close()

	// Step 2: Generate an access token for the target service account
	accessToken, err := generateAccessToken(ctx, credentialsClient, cfg)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to generate access token: %v", err), http.StatusInternalServerError)
		return
	}

	// Step 3: Create storage client with the generated token
	storageClient, err := createStorageClient(ctx, accessToken)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create storage client: %v", err), http.StatusInternalServerError)
		return
	}
	defer storageClient.Close()

	// Step 4: List objects in the target bucket
	if err := listBucketObjects(ctx, storageClient, cfg.TargetBucketName, w); err != nil {
		http.Error(w, fmt.Sprintf("Error listing objects: %v", err), http.StatusInternalServerError)
		return
	}
}
