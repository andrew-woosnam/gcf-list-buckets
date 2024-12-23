#!/bin/bash

# Set strict mode
set -euo pipefail

# Default Configuration Variables
SERVICE_ACCOUNT_KEY="${1}"
TARGET_PROJECT="${2:-striped-device-445917-b7}"
COMPUTE_PROJECT="${3:-proj-awoosnam}"
BUCKET_NAME="${4:-gs://tickleface-gcs}"
SERVICE_ACCOUNT="${5:-576375071060-compute@developer.gserviceaccount.com}"
TARGET_CONFIG="${6:-target-account}"
COMPUTE_CONFIG="${7:-compute-account}"

# Global status flag
GLOBAL_STATUS=0

# Logging helper
log() {
    local level=$1
    local message=$2
    case "$level" in
        INFO) echo -e "[INFO] $message" ;;
        SUCCESS) echo -e "\033[1;32m✓ $message\033[0m" ;;
        ERROR)
            echo -e "\033[1;31m✗ $message\033[0m" >&2
            GLOBAL_STATUS=1 # Set global failure
            ;;
        *) echo -e "[LOG] $message" ;;
    esac
}

# Error handling helper
handle_error() {
    log ERROR "$1"
    exit 1
}

# Pre-checks
command -v gcloud >/dev/null || handle_error "gcloud is not installed. Please install it."
command -v jq >/dev/null || handle_error "jq is not installed. Please install it."

[ -f "$SERVICE_ACCOUNT_KEY" ] || handle_error "Service account key file not found: $SERVICE_ACCOUNT_KEY"
[ -r "$SERVICE_ACCOUNT_KEY" ] || handle_error "Service account key file is not readable."

# Function to activate configuration
activate_config() {
    local config_name=$1
    log INFO "Activating configuration: $config_name"
    gcloud config configurations activate "$config_name" || handle_error "Failed to activate configuration $config_name."
    log SUCCESS "Configuration $config_name activated."
}

# Function to check IAM permissions
check_iam_permissions() {
    local project=$1
    log INFO "Checking IAM permissions for $SERVICE_ACCOUNT in project $project"
    local policy
    policy=$(gcloud projects get-iam-policy "$project" --format=json)
    if echo "$policy" | jq -e ".bindings[] | select(.members[] | contains(\"$SERVICE_ACCOUNT\"))" >/dev/null; then
        log SUCCESS "$SERVICE_ACCOUNT has permissions in project $project"
    else
        log ERROR "$SERVICE_ACCOUNT does not have permissions in project $project"
    fi
}

# Function to check bucket-level IAM
check_bucket_iam_permissions() {
    log INFO "Checking IAM permissions for $SERVICE_ACCOUNT on bucket $BUCKET_NAME"
    local policy
    policy=$(gcloud storage buckets get-iam-policy "${BUCKET_NAME#/gs://}" --format=json)
    if echo "$policy" | jq -e ".bindings[] | select(.members[] | contains(\"$SERVICE_ACCOUNT\"))" >/dev/null; then
        log SUCCESS "$SERVICE_ACCOUNT has permissions on bucket $BUCKET_NAME"
    else
        log ERROR "$SERVICE_ACCOUNT does not have permissions on bucket $BUCKET_NAME"
    fi
}

# Function to validate and enable Requester Pays
validate_requester_pays() {
    log INFO "Checking if Requester Pays is enabled on $BUCKET_NAME"
    local status
    status=$(gcloud storage buckets describe "${BUCKET_NAME#/gs://}" --format="value(requesterPays)")
    if [ "$status" == "True" ]; then
        log SUCCESS "Requester Pays is enabled on $BUCKET_NAME"
    else
        log ERROR "Requester Pays is not enabled on $BUCKET_NAME"
    fi
}

# Function to check and enable Uniform Bucket-Level Access (UBLA)
check_ubla() {
    log INFO "Checking Uniform Bucket-Level Access (UBLA) for $BUCKET_NAME"
    local ubla_status
    ubla_status=$(gcloud storage buckets describe "${BUCKET_NAME#/gs://}" --format="value(uniformBucketLevelAccess.enabled)")
    if [ "$ubla_status" == "True" ]; then
        log SUCCESS "Uniform Bucket-Level Access is enabled for $BUCKET_NAME"
    else
        log ERROR "Uniform Bucket-Level Access is not enabled for $BUCKET_NAME"
        read -p "Would you like to enable UBLA on $BUCKET_NAME? (y/N): " enable_ubla
        if [[ "$enable_ubla" =~ ^[Yy]$ ]]; then
            gcloud storage buckets update "${BUCKET_NAME#/gs://}" --uniform-bucket-level-access || handle_error "Failed to enable UBLA."
            log SUCCESS "Uniform Bucket-Level Access enabled for $BUCKET_NAME"

            # Wait for propagation and re-check
            sleep 5
            ubla_status=$(gcloud storage buckets describe "${BUCKET_NAME#/gs://}" --format="value(uniformBucketLevelAccess.enabled)")
            if [ "$ubla_status" == "True" ]; then
                log SUCCESS "UBLA is now enabled and persistent for $BUCKET_NAME"
            else
                log ERROR "UBLA failed to persist on $BUCKET_NAME. It may require further investigation or additional permissions."
            fi
        fi
    fi
}

# Function to check billing status
check_billing_status() {
    local project=$1
    log INFO "Checking billing status for project $project"
    local status
    status=$(gcloud beta billing projects describe "$project" --format="value(billingEnabled)")
    if [ "$status" == "True" ]; then
        log SUCCESS "Billing is enabled for project $project"
    else
        handle_error "Billing is not enabled for project $project"
    fi
}

# Function to test bucket access
test_bucket_access() {
    local user_project=$1
    log INFO "Testing access to $BUCKET_NAME with userProject $user_project"
    local token
    token=$(gcloud auth print-access-token) || handle_error "Failed to generate access token."
    curl -s -H "Authorization: Bearer $token" \
        "https://storage.googleapis.com/storage/v1/b/${BUCKET_NAME#/gs://}/o?userProject=$user_project" -o response.json

    if grep -q "403" response.json; then
        log ERROR "Bucket access failed. Response: $(cat response.json)"
    else
        log SUCCESS "Bucket access succeeded."
    fi
    rm -f response.json
}

# Main validation steps
activate_config "$TARGET_CONFIG"
check_iam_permissions "$TARGET_PROJECT"
check_bucket_iam_permissions
validate_requester_pays
check_ubla

activate_config "$COMPUTE_CONFIG"
check_billing_status "$COMPUTE_PROJECT"

log INFO "Activating service account for Compute Project"
gcloud auth activate-service-account "$SERVICE_ACCOUNT" --key-file="$SERVICE_ACCOUNT_KEY" --project="$COMPUTE_PROJECT" || handle_error "Failed to activate service account."

test_bucket_access "$COMPUTE_PROJECT"

# Final status
if [ "$GLOBAL_STATUS" -eq 0 ]; then
    log SUCCESS "Validation completed successfully."
else
    log ERROR "Validation completed with errors. Check logs for details."
    exit 1
fi
