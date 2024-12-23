We have 2 main options for allowing GCS access from AWS (there may be others, but these are the main 2 I came across):

### **Option 1: Service Account with Long-Lived Credentials**  
Using a Google Cloud service account with a JSON key file is a straightforward way to authenticate the Lambda function. The key is securely stored and provides access to GCS. This method is simple and quick to set up, but it relies on static credentials, which pose a security risk if exposed, and requires manual key rotation and secure storage. 

### **Option 2: Temporary Credentials with Workload Identity Federation (Preferred)**  
Workload Identity Federation (WIF) enables the Lambda function to authenticate with GCS using temporary credentials obtained via AWS IAM roles. This approach provides fine-grained control and eliminates the need for static credentials and manual credential rotation. 

---

### **Setting Up Workload Identity Federation**

#### **Step 1: Configure Workload Identity Federation in GCP**
1. **Create a Workload Identity Pool**:
   - In the GCP Console, navigate to **IAM & Admin > Workload Identity Federation**.
   - Create a new workload identity pool (e.g., `aws-pool`).

2. **Add an Identity Provider**:
   - In the workload identity pool, add an AWS Identity Provider

3. **Bind a GCP Service Account**:
   - Create or use an existing GCP service account (e.g., `gcs-access@your-project.iam.gserviceaccount.com`).
   - Assign the `Storage Object Viewer` role to this service account for the GCS bucket.
   - Bind the service account to the identity provider in your workload identity pool.


#### **Step 2: Set Up AWS Lambda to Use Temporary Credentials**
1. **Create an IAM Role for Lambda**:
   - Assign an IAM role to the Lambda function with a trust policy that allows it to assume the role.

2. **Configure Environment Variables**:
   - Add the following environment variables to the Lambda configuration:
     - `AWS_ROLE_ARN`: The ARN of the IAM role used for authentication.
     - `GCP_TARGET_PRINCIPAL`: The GCP service account email (e.g., `gcs-access@your-project.iam.gserviceaccount.com`).

3. **Authenticate and Access GCS**:
   - Use the `google.auth` library to exchange AWS credentials for GCP credentials and access GCS.

---

## **Example in Go**
Below is an example Go implementation of how we can authenticate and access GCS using Workload Identity Federation:

```go
package main

import (
	"context"
	"fmt"
	"io/ioutil"

	"cloud.google.com/go/storage"
	"google.golang.org/api/impersonate"
	"google.golang.org/api/option"
)

// Fetch temporary credentials from Workload Identity Federation
func getTemporaryGCSClient(ctx context.Context, targetServiceAccount string) (*storage.Client, error) {
	// Define the impersonation configuration
	ts, err := impersonate.NewTokenSource(ctx, impersonate.CredentialsConfig{
		TargetPrincipal: targetServiceAccount,
		Scopes:          []string{"https://www.googleapis.com/auth/cloud-platform"},
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create token source: %v", err)
	}

	// Create the GCS client
	client, err := storage.NewClient(ctx, option.WithTokenSource(ts))
	if err != nil {
		return nil, fmt.Errorf("failed to create GCS client: %v", err)
	}

	return client, nil
}

// Read a file from GCS
func readGCSFile(ctx context.Context, client *storage.Client, bucketName, objectName string) (string, error) {
	bucket := client.Bucket(bucketName)
	object := bucket.Object(objectName)
	reader, err := object.NewReader(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to create reader for object: %v", err)
	}
	defer reader.Close()

	data, err := ioutil.ReadAll(reader)
	if err != nil {
		return "", fmt.Errorf("failed to read object data: %v", err)
	}

	return string(data), nil
}

func main() {
	ctx := context.Background()

	// Replace with your GCP Service Account email and GCS details
	targetServiceAccount := "your-service-account@your-project.iam.gserviceaccount.com"
	bucketName := "your-gcs-bucket"
	objectName := "your-object.txt"

	// Get a temporary GCS client
	client, err := getTemporaryGCSClient(ctx, targetServiceAccount)
	if err != nil {
		fmt.Printf("Error creating GCS client: %v\n", err)
		return
	}
	defer client.Close()

	// Read the file from GCS
	content, err := readGCSFile(ctx, client, bucketName, objectName)
	if err != nil {
		fmt.Printf("Error reading GCS file: %v\n", err)
		return
	}
	fmt.Printf("File Content: %s\n", content)
}
```

---
