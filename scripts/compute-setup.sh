#!/bin/bash

# Script: compute-setup.sh
# Purpose: Set up a Cloud Function in the Compute Project and output its Service Account ID using interactive authentication.

set -euo pipefail

# Args
GO_FUNC_FILE="${1:-}"
GO_MOD_FILE="${2:-}"

source config.env

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

# Input Validation
validate_inputs() {
    [ -n "$COMPUTE_PROJECT" ] || log ERROR "Compute project ID is required."
    [ -n "$GO_FUNC_FILE" ] && [ -f "$GO_FUNC_FILE" ] || log ERROR "Valid Go function file path is required."
    [ -n "$GO_MOD_FILE" ] && [ -f "$GO_MOD_FILE" ] || log ERROR "Valid go.mod file path is required."
    command -v gcloud >/dev/null || log ERROR "gcloud is not installed. Please install it."
    log SUCCESS "Input validation completed."
}

# Check Authentication and Active Project
check_auth_and_project() {
    log INFO "Checking authentication and active project..."
    local active_account active_project
    active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || echo "")
    active_project=$(gcloud config get-value project 2>/dev/null || echo "")

    if [[ -z "$active_account" || -z "$active_project" ]]; then
        log ERROR "No active account or project detected. Please authenticate and set a project."
    fi

    log INFO "Current active account: $active_account"
    log INFO "Current active project: $active_project"

    if [[ "$active_project" != "$COMPUTE_PROJECT" ]]; then
        log INFO "Active project ($active_project) does not match the expected project ($COMPUTE_PROJECT)."
        read -p "Do you want to re-authenticate and set the correct project? (y/n): " -r choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            authenticate_and_set_project
        else
            log ERROR "Aborted by user. Ensure the correct project is active before running the script."
        fi
    else
        log SUCCESS "Authentication and project match verified."
    fi
}

# Authenticate and Set Project
authenticate_and_set_project() {
    log INFO "Authenticating interactively. Follow the prompts to log in."
    gcloud auth login || log ERROR "Authentication failed."
    gcloud config set project "$COMPUTE_PROJECT" || log ERROR "Failed to set project: $COMPUTE_PROJECT."
    log SUCCESS "Authenticated and active project set to $COMPUTE_PROJECT."
}

# Create or Retrieve Service Account
create_or_get_service_account() {
    SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT_NAME@$COMPUTE_PROJECT.iam.gserviceaccount.com"
    if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &>/dev/null; then
        log INFO "Creating service account: $SERVICE_ACCOUNT_NAME."
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --description="Service account for Cloud Function" \
            --display-name="Cloud Function Service Account" || log ERROR "Failed to create service account."
    fi
    log SUCCESS "Service account ready: $SERVICE_ACCOUNT_EMAIL."
}

# Grant Necessary Roles
grant_roles() {
    log INFO "Granting roles to service account: $SERVICE_ACCOUNT_EMAIL."
    for role in roles/cloudfunctions.admin roles/iam.serviceAccountUser roles/serviceusage.serviceUsageConsumer; do
        gcloud projects add-iam-policy-binding "$COMPUTE_PROJECT" \
            --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
            --role="$role" --quiet || log ERROR "Failed to grant role $role."
    done
    log SUCCESS "Roles assigned to $SERVICE_ACCOUNT_EMAIL."
}

# Deploy Cloud Function
deploy_cloud_function() {
    if gcloud functions describe "$CLOUD_FUNC_NAME" --region="$REGION" &>/dev/null; then
        log SUCCESS "Cloud Function $CLOUD_FUNC_NAME already exists."
        return
    fi

    log INFO "Deploying/Updating Cloud Function: $CLOUD_FUNC_NAME with env vars."
    mkdir -p ./function
    cp "$GO_FUNC_FILE" ./function/main.go
    cp "$GO_MOD_FILE" ./function/go.mod

    gcloud functions deploy "$CLOUD_FUNC_NAME" \
        --region="$REGION" \
        --runtime="$GO_RUNTIME" \
        --entry-point="ListBucketObjects" \
        --source="./function" \
        --trigger-http \
        --gen2 \
        --service-account="$SERVICE_ACCOUNT_EMAIL" \
        --allow-unauthenticated \
        --update-env-vars="STORAGE_BUCKET=$BUCKET_NAME,CLOUD_FUNC_SA=$SERVICE_ACCOUNT_EMAIL,BILLING_PROJECT=$COMPUTE_PROJECT,GOOGLE_API_GO_CLIENT_LOG=debug" || log ERROR "Failed to deploy/update Cloud Function."

    rm -rf ./function
    echo "$SERVICE_ACCOUNT_EMAIL" >cloud-func-service-account.txt
    log SUCCESS "Cloud Function deployed/updated and service account saved."
}

# Main Script Execution
main() {
    validate_inputs
    check_auth_and_project
    create_or_get_service_account
    grant_roles
    deploy_cloud_function
}

main "$@"
