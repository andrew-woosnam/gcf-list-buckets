# Compute Account IAM Setup

## Overview
In the compute account, IAM roles and policies are created using Terraform to manage permissions for serverless functions and service accounts. This ensures secure access to resources like message queues, KMS, and other necessary AWS / GCP components.

## AWS Implementation

Here's the following IAM as configured by Terraform when the compute account is set up in AWS:

### IAM Roles / Policies

- **Mothership Service Account Role**: `cds_mothership_service_account_iam_role`
    - Attached Policies:
        - **SQS Access Policy (`cds_sqs_consumption_iam_policy`)** grants permission to:
            - Receive SQS messages:
                - `sqs:ReceiveMessage`
            - Delete SQS messages:
                - `sqs:DeleteMessage`
            - Get queue attributes:
                - `sqs:GetQueueAttributes`
        - **KMS Encryption Policy (`cds_kms_encryption_iam_policy`)** grants permission to:
            - Encrypt data using KMS:
                - `kms:Encrypt`

- **Scanner Lambda Role**: `cds_scanner_lambda_execution_role`
    - Attached Policy:
        - **Scanner Lambda Policy (`cds_scanner_lambda_iam_policy`)** grants permission to:
            - Read S3 objects:
                - `s3:GetObject`
            - Send/receive messages in SQS:
                - `sqs:SendMessage`
                - `sqs:ReceiveMessage`
                - `sqs:DeleteMessage`
                - `sqs:GetQueueAttributes`
            - Decrypt data using KMS:
                - `kms:Decrypt`
            - Write logs to CloudWatch:
                - `logs:CreateLogGroup`
                - `logs:CreateLogStream`
                - `logs:PutLogEvents`

- **Crawler Lambda Role**: `cds_crawler_lambda_execution_role`
    - Attached Policy:
        - **Crawler Lambda Policy (`cds_crawler_lambda_iam_policy`)** grants permission to:
            - List S3 buckets:
                - `s3:ListBucket`
            - Send/receive messages in SQS:
                - `sqs:SendMessage`
                - `sqs:ReceiveMessage`
                - `sqs:DeleteMessage`
                - `sqs:GetQueueAttributes`
            - Decrypt data using KMS:
                - `kms:Decrypt`
            - Write logs to CloudWatch:
                - `logs:CreateLogGroup`
                - `logs:CreateLogStream`
                - `logs:PutLogEvents`

- **Control Lambda Role**: `cds_control_lambda_execution_role`
    - Attached Policy:
        - **Control Lambda Policy (`cds_control_lambda_iam_policy`)** grants permission to:
            - Manage SQS messages:
                - `sqs:SendMessage`
                - `sqs:ReceiveMessage`
                - `sqs:DeleteMessage`
                - `sqs:GetQueueAttributes`
            - Access secrets in Secrets Manager:
                - `secretsmanager:GetSecretValue`
            - Decrypt data using KMS:
                - `kms:Decrypt`
            - Write logs to CloudWatch:
                - `logs:CreateLogGroup`
                - `logs:CreateLogStream`
                - `logs:PutLogEvents`

---

## GCP Implementation

Here are the equivalents we can use in GCP:

### Service Accounts
#### **CDS Cloud Function Service Account**
- Used by GCP Cloud Functions for accessing GCS and publishing to Pub/Sub.
- Permissions:
  - `roles/storage.objectViewer`: Read access to GCS.
  - `roles/pubsub.publisher`: Publish messages to Pub/Sub.
  - `roles/cloudkms.cryptoKeyDecrypter`: Decrypt data using KMS.

#### **CDS Mothership Service Account**
- Used by the external server to access Pub/Sub and KMS.
- Permissions:
  - `roles/pubsub.subscriber`: Consume messages from Pub/Sub.
  - `roles/cloudkms.cryptoKeyEncrypter`: Encrypt data using KMS.

### Sample Terraform Definitions
1. **Create Service Accounts**:
   ```hcl
   resource "google_service_account" "cds_cloud_function_service_account" {
     account_id   = "cds-cloud-function-service-account"
     display_name = "CDS Cloud Function Service Account"
   }

   resource "google_service_account" "cds_mothership_service_account" {
     account_id   = "cds-mothership-service-account"
     display_name = "CDS Mothership Service Account"
   }
   ```

2. **Assign Roles to Grant Permissions**:
    ```hcl
    resource "google_project_iam_member" "cds_cloud_function_storage_access" {
    project = var.project_id
    role    = "roles/storage.objectViewer"
    member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
    }

    resource "google_project_iam_member" "cds_cloud_function_pubsub_access" {
    project = var.project_id
    role    = "roles/pubsub.publisher"
    member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
    }

    resource "google_project_iam_member" "cds_cloud_function_kms_decrypt" {
    project = var.project_id
    role    = "roles/cloudkms.cryptoKeyDecrypter"
    member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
    }

    resource "google_project_iam_member" "cds_pubsub_access" {
    project = var.project_id
    role    = "roles/pubsub.subscriber"
    member  = "serviceAccount:${google_service_account.cds_mothership_service_account.email}"
    }

    resource "google_project_iam_member" "cds_kms_encrypt" {
    project = var.project_id
    role    = "roles/cloudkms.cryptoKeyEncrypter"
    member  = "serviceAccount:${google_service_account.cds_mothership_service_account.email}"
    }

    ```

3. **Deploy Cloud Functions** (CDS Cloud Function Service Account):
   ```hcl
   resource "google_cloudfunctions_function" "example" {
     name        = "example-function"
     description = "An example Cloud Function"
     runtime     = "go122"
     entry_point = "functionEntryPoint"

     source_archive_bucket = "${google_storage_bucket.source_bucket.name}"
     source_archive_object = "${google_storage_bucket_object.source_archive.name}"
     trigger_http          = true

     service_account_email = google_service_account.cds_cloud_function_service_account.email
   }
   ```

4. **Grant Permissions to Impersonate Service Accounts** (CDS Mothership Service Account):
    ```hcl
    resource "google_service_account_iam_member" "impersonation_role" {
    service_account_id = google_service_account.cds_mothership_service_account.name
    role               = "roles/iam.serviceAccountTokenCreator"
    member             = "user:${var.user_email}"
    }
    ```

---

# Target Account IAM Setup

## Overview
The target account is configured by users (following instructions from the Zero Trust dashboard) to grant CDS components the permissions they need to access objects in cloud storage.

## AWS Implementation

1. **Create a New IAM Role**:
   - Trusted entity: AWS account (Cloudflare CDS account ID).
   - Add an **External ID** to prevent the confused deputy problem.

2. **Attach Permissions**:
   - S3 Access:
     - `s3:GetObject`
     - `s3:ListBucket`
   - Example Policy:
     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Action": [
             "s3:GetObject",
             "s3:ListBucket"
           ],
           "Resource": ["arn:aws:s3:::bucket_name/*"]
         }
       ]
     }
     ```

3. **Provide Role ARN**:
   - Share with Cloudflare via Zero Trust dashboard.

## GCP Implementation

1. **Grant Bucket Access**:
   - Assign the `roles/storage.objectViewer` role to the Alien Service Account.
   ```bash
   gcloud storage buckets add-iam-policy-binding gs://[BUCKET_NAME] \
       --member="serviceAccount:[SERVICE_ACCOUNT_NAME]@[PROJECT_ID].iam.gserviceaccount.com" \
       --role="roles/storage.objectViewer"
   ```

2. **Verify Access**:
   - Ensure the Alien Cloud Functions can access objects in the GCS bucket.

---

