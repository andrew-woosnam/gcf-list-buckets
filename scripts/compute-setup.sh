#!/bin/bash

# Script: compute-setup.sh
# Purpose: Set up Cloud Function in the Compute Project and output its Service Account ID using interactive authentication.

set -euo pipefail

# Configuration Variables
COMPUTE_PROJECT="${1:-}"
REGION="${2:-us-west1}"
CLOUD_FUNC_NAME="${3:-new-cloud-function}"
GO_RUNTIME="${4:-go122}"
SERVICE_ACCOUNT_NAME="${5:-cloud-function-sa}"  # New Service Account Name

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
    [ -n "$COMPUTE_PROJECT" ] || log ERROR "Compute project ID is required as the first argument."
    command -v gcloud >/dev/null || log ERROR "gcloud is not installed. Please install it."
    log SUCCESS "Input validation completed."
}

# Authenticate Interactively
authenticate_and_set_project() {
    log INFO "Authenticating interactively. Follow the prompts to log in."
    gcloud auth login || log ERROR "Failed to authenticate interactively."
    log SUCCESS "Authenticated successfully."

    log INFO "Setting active project to: $COMPUTE_PROJECT"
    gcloud config set project "$COMPUTE_PROJECT" || log ERROR "Failed to set project: $COMPUTE_PROJECT"
    log SUCCESS "Active project set to $COMPUTE_PROJECT."
}

# Create Service Account
create_service_account() {
    log INFO "Creating new service account: $SERVICE_ACCOUNT_NAME in project $COMPUTE_PROJECT"
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --description="Service account for Cloud Function" \
        --display-name="Cloud Function Service Account" || log ERROR "Failed to create service account."

    SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT_NAME@$COMPUTE_PROJECT.iam.gserviceaccount.com"
    log SUCCESS "Service account created: $SERVICE_ACCOUNT_EMAIL"
}

# Grant Roles to Service Account
grant_roles_to_service_account() {
    log INFO "Granting necessary roles to service account: $SERVICE_ACCOUNT_EMAIL"

    gcloud projects add-iam-policy-binding "$COMPUTE_PROJECT" \
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
        --role="roles/cloudfunctions.admin" || log ERROR "Failed to grant Cloud Functions Admin role."

    gcloud projects add-iam-policy-binding "$COMPUTE_PROJECT" \
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
        --role="roles/iam.serviceAccountUser" || log ERROR "Failed to grant Service Account User role."

    log SUCCESS "Necessary roles granted to $SERVICE_ACCOUNT_EMAIL"
}

# Deploy Cloud Function
deploy_cloud_function() {
    log INFO "Deploying Cloud Function: $CLOUD_FUNC_NAME in project $COMPUTE_PROJECT with runtime $GO_RUNTIME"
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
        --service-account="$SERVICE_ACCOUNT_EMAIL" || log ERROR "Failed to deploy Cloud Function."

    log SUCCESS "Cloud Function $CLOUD_FUNC_NAME deployed with service account: $SERVICE_ACCOUNT_EMAIL"

    rm -rf ./function
    echo "$SERVICE_ACCOUNT_EMAIL" >cloud-func-service-account.txt
    log SUCCESS "Cloud Function Service Account saved to: cloud-func-service-account.txt"
}

# Main Script Execution
main() {
    validate_inputs
    authenticate_and_set_project
    create_service_account
    grant_roles_to_service_account
    deploy_cloud_function
}

main "$@"
