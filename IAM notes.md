### Notes: Setting Up Federated Identities for AWS IAM to GCP Integration (GCS Access)

---

#### Step 1: Configure AWS IAM Role
**Goal**: Create an IAM Role to enable AWS workloads (e.g., Lambda, ECS) to obtain temporary credentials for GCP access.

1. **Create an AWS IAM Role**:
   - Navigate to AWS Management Console > IAM > Roles > Create Role.
   - Select **Custom trust policy** as the trusted entity type.
   - Define the following trust policy:
     ```json
     {
         "Version": "2012-10-17",
         "Statement": [
             {
                 "Effect": "Allow",
                 "Principal": {
                     "Federated": "arn:aws:iam::123456789012:oidc-provider/sts.amazonaws.com"
                 },
                 "Action": "sts:AssumeRoleWithWebIdentity",
                 "Condition": {
                     "StringEquals": {
                         "sts:aud": "sts.amazonaws.com"
                     }
                 }
             }
         ]
     }
     ```
     Replace `123456789012` with your AWS account ID.

2. **Assign Permissions to the Role**:
   - Attach an inline policy granting the necessary permissions to the workload.

3. **Note the Role ARN**:
   - Record the ARN of the role (e.g., `arn:aws:iam::123456789012:role/MyFederatedRole`).

4. **Attach the Role to Your AWS Workload**:
   - Assign this role to the Lambda function, ECS task, or other workload that requires access.

---

#### Step 2: Create a GCP Service Account
**Goal**: Map the AWS IAM Role to a GCP Service Account.

1. **Create a Service Account**:
   - Navigate to the GCP Console > IAM & Admin > Service Accounts.
   - Create a new Service Account (e.g., `gcs-access-service-account`).
   - Assign appropriate permissions:
     - `roles/storage.objectViewer` to read objects in GCS.
     - If we need broader control (e.g. event notifications), `roles/storage.objectAdmin` might be necessary.

2. **Note the Service Account id** (e.g., `gcs-access-service-account@your-project.iam.gserviceaccount.com`).

---

#### Step 3: Enable Workload Identity Federation in GCP
**Goal**: Link AWS IAM to the GCP Service Account.

1. **Create a Workload Identity Pool**:
   - Navigate to GCP > IAM & Admin > Workload Identity Federation.
   - Click **Create Pool**:
     - **Name**: `aws-pool`.
     - **Description**: Federated access for AWS.
     - **Provider Type**: AWS.

2. **Add a Workload Identity Provider**:
   - In the pool, click **Add Provider**:
     - **Name**: `aws-provider`.
     - **Description**: Links AWS credentials to GCP.
     - **AWS Account ID**: Replace with your AWS account ID.
     - **Audience**: `sts.amazonaws.com` (default).

3. **Map AWS Role to GCP Service Account**:
   - Use `gcloud` to add an IAM policy binding:
     ```bash
     gcloud iam service-accounts add-iam-policy-binding gcs-access-service-account@your-project.iam.gserviceaccount.com \
       --role="roles/iam.workloadIdentityUser" \
       --member="principalSet://iam.googleapis.com/projects/[PROJECT_ID]/locations/global/workloadIdentityPools/aws-pool/attribute.aws-role/arn:aws:iam::123456789012:role/MyFederatedRole"
     ```
   - Replace placeholders:
     - `[PROJECT_ID]`: Your GCP project ID.
     - `123456789012`: Your AWS account ID.
     - `MyFederatedRole`: Your AWS IAM Role name.

---

#### Step 4: Download ADC Configuration for Federated Identities
**Goal**: Configure workload to be able to authenticate with GCP.

1. Go to **Workload Identity Pool** in GCP.
2. Select your pool and click **Download Configuration**.
3. Save the file (e.g., `aws-pool-config.json`).
4. Include this file in your AWS workload environment.

---

#### Step 5: Configure the Workload
**Goal**: Enable GCP Client Libraries in AWS to access GCS.

1. Set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/aws-pool-config.json
   ```

2. Use GCP Client Libraries (e.g., `google-cloud-storage`).

---

#### Validation
**Test Access to GCS**:
Here’s how I implemented the test in **Go**:

1. **Install the library**:
   ```bash
   go get cloud.google.com/go/storage
   ```

2. **Code to List Buckets**:
   ```go
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
   ```

3. **Run the Program**:
   - Ensure `GOOGLE_APPLICATION_CREDENTIALS` points to the configuration file.
   - Execute the program:
     ```bash
     go run main.go
     ```

---

#### Expected Outcome
- The program should print a list of GCS buckets:
  ```
  Listing buckets:
  - bucket-1
  - bucket-2
  - bucket-3
  ```