#!/bin/bash

# Script: target-setup.sh
# Purpose: Set up GCS bucket in the Target Project and configure IAM permissions for Cloud Function Service Account.

set -euo pipefail

# Configuration Variables
TARGET_PROJECT="${1:-}"
SERVICE_ACCOUNT_KEY="${2:-}"
REGION="${3:-us-west1}"
BUCKET_NAME="${4:-new-target-bucket}"
ENABLE_UBLA="${5:-false}" # Enable Uniform Bucket-Level Access (default: false)
CLOUD_FUNC_SA_FILE="cloud-func-service-account.txt"

# Logging Helper
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        INFO) echo -e "[INFO] $message" ;;
        SUCCESS) echo -e "\033[1;32m✓ $message\033[0m" ;;
        ERROR)
            echo -e "\033[1;31m✗ $message\033[0m" >&2
            exit 1
            ;;
        *) echo -e "[LOG] $message" ;;
    esac
}

# Validate Inputs
validate_inputs() {
    [ -n "$SERVICE_ACCOUNT_KEY" ] || log ERROR "Target service account key is required as the first argument."
    [ -n "$TARGET_PROJECT" ] || log ERROR "Target project ID is required as the second argument."

    [ -f "$SERVICE_ACCOUNT_KEY" ] || log ERROR "Service account key file not found: $SERVICE_ACCOUNT_KEY"
    [ -f "$CLOUD_FUNC_SA_FILE" ] || log ERROR "Cloud Function Service Account file not found: $CLOUD_FUNC_SA_FILE"

    command -v gcloud >/dev/null || log ERROR "gcloud is not installed. Please install it."
    log SUCCESS "Input validation completed."
}

# Authenticate and Set Project
authenticate_and_set_project() {
    log INFO "Authenticating with service account key: $SERVICE_ACCOUNT_KEY"
    gcloud auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY" || log ERROR "Failed to authenticate."
    log SUCCESS "Authenticated successfully."

    log INFO "Setting active project to: $TARGET_PROJECT"
    gcloud config set project "$TARGET_PROJECT" || log ERROR "Failed to set project: $TARGET_PROJECT"
    log SUCCESS "Active project set to $TARGET_PROJECT."
}

# Create GCS Bucket
create_bucket() {
    log INFO "Checking if bucket $BUCKET_NAME already exists in project $TARGET_PROJECT"
    if gcloud storage buckets list --project="$TARGET_PROJECT" --format="value(name)" | grep -q "^${BUCKET_NAME#/gs://}$"; then
        log SUCCESS "Bucket $BUCKET_NAME already exists."
    else
        log INFO "Creating GCS bucket: $BUCKET_NAME in project $TARGET_PROJECT"
        gcloud storage buckets create "$BUCKET_NAME" --project="$TARGET_PROJECT" --location="$REGION" || log ERROR "Failed to create GCS bucket."
        log SUCCESS "GCS bucket $BUCKET_NAME created in project $TARGET_PROJECT."
    fi

    # Optional: Enable UBLA
    if [ "$ENABLE_UBLA" == "true" ]; then
        log INFO "Enabling Uniform Bucket-Level Access (UBLA) for $BUCKET_NAME"
        gcloud storage buckets update "$BUCKET_NAME" --uniform-bucket-level-access || log ERROR "Failed to enable UBLA."
        log SUCCESS "UBLA enabled for $BUCKET_NAME."
    fi
}

# Configure Bucket IAM
configure_bucket_iam() {
    CLOUD_FUNC_SA=$(cat "$CLOUD_FUNC_SA_FILE")
    log INFO "Granting Cloud Function service account ($CLOUD_FUNC_SA) access to GCS bucket: $BUCKET_NAME"
    gcloud storage buckets add-iam-policy-binding "$BUCKET_NAME" \
        --member="serviceAccount:$CLOUD_FUNC_SA" \
        --role="roles/storage.objectViewer" \
        --project="$TARGET_PROJECT" || log ERROR "Failed to grant IAM permissions."
    log SUCCESS "IAM permissions granted: $CLOUD_FUNC_SA can view $BUCKET_NAME."
}

# Main Script Execution
main() {
    validate_inputs
    authenticate_and_set_project
    create_bucket
    configure_bucket_iam
}

main "$@"
