#!/bin/bash

# Fixed: target-setup.sh
# Purpose: Set up GCS bucket in the Target Project and configure IAM permissions for Cloud Function Service Account.

set -euo pipefail

source config.env
CLOUD_FUNC_SA_FILE="cloud-func-service-account.txt"

# Logging Helper
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        INFO) echo -e "[INFO] $message" ;;
        SUCCESS) echo -e "\033[1;32m✓ $message\033[0m" ;;
        ERROR) echo -e "\033[1;31m✗ $message\033[0m" >&2
            exit 1
            ;;
        *) echo -e "[LOG] $message" ;;
    esac
}

# Validate Inputs
validate_inputs() {
    [ -n "$TARGET_PROJECT" ] || log ERROR "Target project ID is required as the first argument."
    [ -f "$CLOUD_FUNC_SA_FILE" ] || log ERROR "Cloud Function Service Account file not found: $CLOUD_FUNC_SA_FILE"
    command -v gcloud >/dev/null || log ERROR "gcloud is not installed. Please install it."
    log SUCCESS "Input validation completed."
}

# Authenticate and Set Project
authenticate_and_set_project() {
    log INFO "Authenticating interactively. Follow the prompts to log in."
    gcloud auth login || log ERROR "Failed to authenticate interactively."
    log SUCCESS "Authenticated successfully."

    log INFO "Setting active project to: $TARGET_PROJECT"
    gcloud config set project "$TARGET_PROJECT" || log ERROR "Failed to set project: $TARGET_PROJECT"
    log SUCCESS "Active project set to $TARGET_PROJECT."
}

# Verify Authentication and Active Project
verify_auth_and_project() {
    log INFO "Verifying authentication and active project..."
    local active_project
    active_project=$(gcloud config get-value project 2>/dev/null || echo "")

    if [[ -z "$active_project" ]]; then
        log ERROR "No active project set. Please authenticate and set a project."
        authenticate_and_set_project
        return
    fi

    if [[ "$active_project" != "$TARGET_PROJECT" ]]; then
        log INFO "Expected project ($TARGET_PROJECT) does not match the active project ($active_project)."
        authenticate_and_set_project
    else
        log SUCCESS "Continuing with active project: $active_project."
    fi
}

# Create GCS Bucket
create_bucket() {
    log INFO "Checking if bucket $BUCKET_NAME already exists in project $TARGET_PROJECT"
    if gcloud storage buckets list --project="$TARGET_PROJECT" --format="value(name)" | grep -q "^$BUCKET_NAME$"; then
        log SUCCESS "Bucket $BUCKET_NAME already exists in project $TARGET_PROJECT."
    else
        log INFO "Creating GCS bucket: gs://$BUCKET_NAME in project $TARGET_PROJECT"
        gcloud storage buckets create "gs://$BUCKET_NAME" \
            --project="$TARGET_PROJECT" \
            --location="$REGION" || log ERROR "Failed to create GCS bucket."
        log SUCCESS "GCS bucket gs://$BUCKET_NAME created in project $TARGET_PROJECT."
    fi

    # Enable Uniform Bucket-Level Access (UBLA) if requested
    if [[ "$ENABLE_UBLA" == "true" ]]; then
        log INFO "Enabling Uniform Bucket-Level Access (UBLA) for gs://$BUCKET_NAME"
        gcloud storage buckets update "gs://$BUCKET_NAME" --uniform-bucket-level-access || log ERROR "Failed to enable UBLA."
        log SUCCESS "UBLA enabled for gs://$BUCKET_NAME."
    fi
}

# Configure Bucket IAM
configure_bucket_iam() {
    local cloud_func_sa
    cloud_func_sa=$(cat "$CLOUD_FUNC_SA_FILE")
    local bucket_url="gs://$BUCKET_NAME"
    log INFO "Granting Cloud Function service account ($cloud_func_sa) access to bucket $bucket_url"

    gcloud storage buckets add-iam-policy-binding "$bucket_url" \
        --member="serviceAccount:$cloud_func_sa" \
        --role="roles/storage.objectViewer" \
        --project="$TARGET_PROJECT" || log ERROR "Failed to grant IAM permissions."
    log SUCCESS "IAM permissions granted for $cloud_func_sa on bucket $bucket_url."
}

upload_file_with_contents() {
    local bucket_url="gs://$BUCKET_NAME"
    local file_name="file1.txt"
    local file_contents="123-45-6789"

    log INFO "Creating file: $file_name with contents: $file_contents"
    echo "$file_contents" > "$file_name" || log ERROR "Failed to create file $file_name with contents."

    log INFO "Uploading $file_name to $bucket_url"
    gcloud storage cp "$file_name" "$bucket_url/" || log ERROR "Failed to upload $file_name to $bucket_url."

    log SUCCESS "File $file_name successfully uploaded to $bucket_url."
    rm -f "$file_name" || log ERROR "Failed to delete local file $file_name."
}

# Main Script Execution
main() {
    validate_inputs
    verify_auth_and_project
    create_bucket
    configure_bucket_iam
    upload_file_with_contents
}

main "$@"
