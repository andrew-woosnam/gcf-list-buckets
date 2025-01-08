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

variable "cloud_func_name" {
  description = "The name of the Cloud Function"
  type        = string
}

variable "docker_image" {
  description = "The Docker image URI for the Cloud Function"
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

# Deploy the Docker-based Cloud Function
resource "google_cloudfunctions_function" "example_function" {
  name        = var.cloud_func_name
  runtime     = "go119" # Runtime is irrelevant for Docker-based deployments
  available_memory_mb = 256
  timeout = 60

  deployment_container {
    image_uri = var.docker_image
  }

  trigger_http = true
  service_account_email = google_service_account.cds_cloud_function_service_account.email
}
