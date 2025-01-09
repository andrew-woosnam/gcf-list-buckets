/*
 * main.tf - Compute Account Setup for GCP
 */

provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "cloud_function_sa" {
  description = "The service account for the Cloud Function"
  type        = string
}

variable "pubsub_topic_id" {
  description = "Pub/Sub topic ID for testing"
  type        = string
  default     = "test-topic"
}

variable "pubsub_subscription_id" {
  description = "Pub/Sub subscription ID for testing"
  type        = string
  default     = "test-subscription"
}

# Service Account
resource "google_service_account" "cds_cloud_function_service_account" {
  account_id   = var.cloud_function_sa
  display_name = "CDS Cloud Function Service Account"
}

# IAM Role Assignments for Cloud Function Service Account
resource "google_project_iam_member" "cds_logging_access" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
}

resource "google_project_iam_member" "cds_pubsub_access" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
}

resource "google_project_iam_member" "cds_service_usage_access" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
}

resource "google_project_iam_member" "cds_storage_viewer_access" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
}

# Pub/Sub Topic
resource "google_pubsub_topic" "test_topic" {
  name = var.pubsub_topic_id
}

# Pub/Sub Subscription
resource "google_pubsub_subscription" "test_subscription" {
  name  = var.pubsub_subscription_id
  topic = google_pubsub_topic.test_topic.id
}

# Grant Service Account Publish Permission
resource "google_project_iam_member" "cds_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
}

# Grant Service Account Subscriber Permission
resource "google_project_iam_member" "cds_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.cds_cloud_function_service_account.email}"
}
