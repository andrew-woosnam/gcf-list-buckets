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

# Verify Authentication and Active Project
verify_auth_and_project() {
    log INFO "Verifying authentication and active project..."

    local active_account
    local active_project

    active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || echo "")
    active_project=$(gcloud config get-value project 2>/dev/null || echo "")

    if [[ -z "$active_account" || -z "$active_project" ]]; then
        log ERROR "No active account or project found. Please authenticate and set a project."
        authenticate_and_set_project
        return
    fi

    log INFO "Current active account: $active_account"
    log INFO "Current active project: $active_project"

    if [[ "$active_project" != "$COMPUTE_PROJECT" ]]; then
        log INFO "Expected project ($COMPUTE_PROJECT) does not match the active project ($active_project)."
    fi

    read -p "Proceed with the current account and project? (Y/N): " -r choice
    if [[ "$choice" != "Y" && "$choice" != "y" ]]; then
        authenticate_and_set_project
    else
        log SUCCESS "Continuing with current authentication and project."
    fi
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
    SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT_NAME@$COMPUTE_PROJECT.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &>/dev/null; then
        log SUCCESS "Service account already exists: $SERVICE_ACCOUNT_EMAIL"
    else
        log INFO "Creating new service account: $SERVICE_ACCOUNT_NAME in project $COMPUTE_PROJECT"
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --description="Service account for Cloud Function" \
            --display-name="Cloud Function Service Account" || log ERROR "Failed to create service account."
        log SUCCESS "Service account created: $SERVICE_ACCOUNT_EMAIL"
    fi
}

# Grant Roles to Service Account
grant_roles_to_service_account() {
    log INFO "Checking and granting necessary roles to service account: $SERVICE_ACCOUNT_EMAIL"

    for role in roles/cloudfunctions.admin roles/iam.serviceAccountUser; do
        if gcloud projects get-iam-policy "$COMPUTE_PROJECT" \
            --flatten="bindings[].members" \
            --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT_EMAIL AND bindings.role:$role" \
            --format="value(bindings.role)" | grep -q "$role"; then
            log INFO "Role $role already assigned to $SERVICE_ACCOUNT_EMAIL"
        else
            gcloud projects add-iam-policy-binding "$COMPUTE_PROJECT" \
                --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
                --role="$role" || log ERROR "Failed to grant role $role."
            log SUCCESS "Role $role granted to $SERVICE_ACCOUNT_EMAIL"
        fi
    done
}

# Deploy Cloud Function
deploy_cloud_function() {
    if gcloud functions describe "$CLOUD_FUNC_NAME" --region="$REGION" &>/dev/null; then
        log SUCCESS "Cloud Function $CLOUD_FUNC_NAME already exists."
    else
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
    fi
}

# Main Script Execution
main() {
    validate_inputs
    verify_auth_and_project
    create_service_account
    grant_roles_to_service_account
    deploy_cloud_function
}

main "$@"
