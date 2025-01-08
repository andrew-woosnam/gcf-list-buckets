/*
 * main.tf - Compute Account Setup for GCP
 *
 * This Terraform configuration sets up the necessary resources and permissions 
 * for a compute account in Google Cloud Platform (GCP). It includes:
 * 
 * 1. Service Accounts:
 *    - CDS Cloud Function Service Account: Used by Cloud Functions to interact 
 *      with Google Cloud Storage (GCS), Pub/Sub, and KMS for decryption.
 *    - CDS Mothership Service Account: Used for Pub/Sub consumption and KMS encryption.
 * 
 * 2. IAM Role Assignments:
 *    - Assigns roles for GCS access, Pub/Sub publishing/subscribing, and KMS operations.
 *    - Grants logging permissions for writing logs to Cloud Logging.
 *    - Includes impersonation permissions for secure access between accounts.
 * 
 * 3. Cloud Function Deployment:
 *    - Creates a storage bucket to host the source archive.
 *    - Deploys an example Cloud Function using the specified service account.
 * 
 * Usage:
 * - Replace placeholder variables (e.g., project ID, region, user email) with actual values.
 * - Initialize and apply the configuration using `terraform init` and `terraform apply`.
 *
 * Notes:
 * - Ensure the source archive path (`path/to/source.zip`) points to your Cloud Function code.
 * - This setup provides a secure and modular foundation for managing serverless 
 *   functions and associated resources in GCP.
 */

provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
variable "project_id" {}
variable "region" {}
variable "user_email" {}

# Service Accounts
resource "google_service_account" "cds_cloud_function_service_account" {
  account_id   = "cds-cloud-function-service-account"
  display_name = "CDS Cloud Function Service Account"
}

resource "google_service_account" "cds_mothership_service_account" {
  account_id   = "cds-mothership-service-account"
  display_name = "CDS Mothership Service Account"
}

# IAM Role Assignments for Cloud Function Service Account
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

resource "google_project_iam_member" "cds_logging_access" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
}

# IAM Role Assignments for CDS Mothership Service Account
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

# Impersonation Permission for CDS Mothership Service Account
resource "google_service_account_iam_member" "impersonation_role" {
  service_account_id = google_service_account.cds_mothership_service_account.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.user_email}"
}

# Cloud Function Deployment
resource "google_storage_bucket" "source_bucket" {
  name          = "${var.project_id}-source-bucket"
  location      = var.region
  force_destroy = true
}

resource "google_storage_bucket_object" "source_archive" {
  name   = "source.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = "path/to/source.zip"
}

resource "google_cloudfunctions_function" "example_function" {
  name        = "example-function"
  description = "An example Cloud Function"
  runtime     = "nodejs16"
  entry_point = "functionEntryPoint"

  source_archive_bucket = google_storage_bucket.source_bucket.name
  source_archive_object = google_storage_bucket_object.source_archive.name
  trigger_http          = true

  service_account_email = google_service_account.cds_cloud_function_service_account.email
}
