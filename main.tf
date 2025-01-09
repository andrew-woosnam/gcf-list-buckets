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
