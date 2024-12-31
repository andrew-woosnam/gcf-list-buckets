#!/bin/bash

# Script: gcp-func-gcs-setup.sh
# Purpose: Manage and set up GCP resources across Compute and Target accounts.
# Requires: A service account key with permissions to manage resources across projects.

set -euo pipefail

# Configuration Variables
SERVICE_ACCOUNT_KEY="${1:-}"
COMPUTE_PROJECT="${2:-}"
TARGET_PROJECT="${3:-}"
REGION="${4:-us-west1}"
CLOUD_FUNC_NAME="${5:-new-cloud-function}"
BUCKET_NAME="${6:-new-target-bucket}"
GO_RUNTIME="${7:-go122}"
ENABLE_UBLA="${8:-false}" # Enable Uniform Bucket-Level Access (default: false)

# Logging Helper
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        INFO) echo -e "[INFO] $message" ;;
        SUCCESS) echo -e "\033[1;32m✓ $message\033[0m" ;;
        ERROR)
            echo -e "\033[1;31m✗ $message\033[0m" >&2
            exit 1 # Immediate exit on error
            ;;
        *) echo -e "[LOG] $message" ;;
    esac
}

# Pre-checks
validate_inputs() {
    # Check if required variables are provided
    [ -n "$SERVICE_ACCOUNT_KEY" ] || log ERROR "Service account key is required as the first argument."
    [ -n "$COMPUTE_PROJECT" ] || log ERROR "Compute project ID is required as the second argument."
    [ -n "$TARGET_PROJECT" ] || log ERROR "Target project ID is required as the third argument."

    # Check if the service account key file exists and is readable
    [ -f "$SERVICE_ACCOUNT_KEY" ] || log ERROR "Service account key file not found: $SERVICE_ACCOUNT_KEY"
    [ -r "$SERVICE_ACCOUNT_KEY" ] || log ERROR "Service account key file is not readable."

    # Check if required commands are installed
    command -v gcloud >/dev/null || log ERROR "gcloud is not installed. Please install it."
    command -v jq >/dev/null || log ERROR "jq is not installed. Please install it."

    # Log successful validation
    log SUCCESS "Input validation completed."
}

# Authenticate Service Account
authenticate_service_account() {
    log INFO "Authenticating with service account key: $SERVICE_ACCOUNT_KEY"
    gcloud auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY" || log ERROR "Failed to authenticate."
    log SUCCESS "Authenticated successfully."
}

# Deploy Cloud Function
deploy_cloud_function() {
    log INFO "Deploying Cloud Function: $CLOUD_FUNC_NAME in project $COMPUTE_PROJECT with Go $GO_RUNTIME"
    gcloud config set project "$COMPUTE_PROJECT" || log ERROR "Failed to set Compute project: $COMPUTE_PROJECT"

    mkdir -p ./function
    cat <<EOF >./function/main.go
package function

import (
	"fmt"
	"net/http"
)

// HelloWorld is a basic Cloud Function.
func HelloWorld(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "Hello, World!")
}
EOF

    cat <<EOF >./function/go.mod
module example.com/function

go 1.22
EOF

    gcloud functions deploy "$CLOUD_FUNC_NAME" \
        --region="$REGION" \
        --runtime="$GO_RUNTIME" \
        --entry-point="HelloWorld" \
        --source="./function" \
        --trigger-http \
        --gen2 \
        --format="value(serviceAccountEmail)" || log ERROR "Failed to deploy Cloud Function."

    CLOUD_FUNC_SA=$(gcloud functions describe "$CLOUD_FUNC_NAME" --region="$REGION" --format="value(serviceAccountEmail)")
    log SUCCESS "Cloud Function $CLOUD_FUNC_NAME deployed with service account: $CLOUD_FUNC_SA"

    # Clean up
    rm -rf ./function
}

# Create GCS Bucket
create_bucket() {
    log INFO "Checking if bucket $BUCKET_NAME already exists in project $TARGET_PROJECT"
    if gcloud storage buckets list --project="$TARGET_PROJECT" --format="value(name)" | grep -q "^${BUCKET_NAME#/gs://}$"; then
        log SUCCESS "Bucket $BUCKET_NAME already exists."
    else
        log INFO "Creating GCS bucket: $BUCKET_NAME in project $TARGET_PROJECT"
        gcloud config set project "$TARGET_PROJECT" || log ERROR "Failed to set Target project: $TARGET_PROJECT"
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
    log INFO "Granting Cloud Function service account access to GCS bucket"
    gcloud storage buckets add-iam-policy-binding "$BUCKET_NAME" \
        --member="serviceAccount:$CLOUD_FUNC_SA" \
        --role="roles/storage.objectViewer" \
        --project="$TARGET_PROJECT" || log ERROR "Failed to grant IAM permissions."
    log SUCCESS "IAM permissions granted: $CLOUD_FUNC_SA can view $BUCKET_NAME."
}

# Main Script Execution
main() {
    validate_inputs
    authenticate_service_account
    deploy_cloud_function
    create_bucket
    configure_bucket_iam

    log SUCCESS "Script completed successfully."
    echo -e "\033[1;34mCloud Function Service Account: $CLOUD_FUNC_SA\033[0m"
}

main "$@"
