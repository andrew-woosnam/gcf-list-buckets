package main

import (
    "context"
    "fmt"
    "log"

    "cloud.google.com/go/storage"
)

func main() {
    // Create a context
    ctx := context.Background()

    // Initialize the GCS client
    client, err := storage.NewClient(ctx)
    if err != nil {
        log.Fatalf("Failed to create GCS client: %v", err)
    }
    defer client.Close()

    // List buckets
    fmt.Println("Listing buckets:")
    it := client.Buckets(ctx, "YOUR_PROJECT_ID") // Replace with GCP project ID
    for {
        bucketAttrs, err := it.Next()
        if err != nil {
            if err.Error() == "iterator: done" {
                break
            }
            log.Fatalf("Error listing buckets: %v", err)
        }
        fmt.Printf("- %s\n", bucketAttrs.Name)
    }
}
