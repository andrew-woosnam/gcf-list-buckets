#!/bin/bash

# Script: compute-setup.sh
# Purpose: Ensure the correct GCP account and project are active, then apply Terraform.

set -euo pipefail

# Variables
PROJECT_ID="${1:-}"
REGION="${2:-us-east1}"

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

    if [[ "$active_project" != "$PROJECT_ID" ]]; then
        log INFO "Active project ($active_project) does not match the expected project ($PROJECT_ID)."
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
    gcloud config set project "$PROJECT_ID" || log ERROR "Failed to set project: $PROJECT_ID."
    log SUCCESS "Authenticated and active project set to $PROJECT_ID."
}

# Initialize and Apply Terraform
apply_terraform() {
    log INFO "Initializing Terraform..."
    terraform init || log ERROR "Terraform initialization failed."

    log INFO "Applying Terraform configuration..."
    terraform apply -var="project_id=$PROJECT_ID" -var="region=$REGION" -auto-approve || log ERROR "Terraform apply failed."
    log SUCCESS "Terraform configuration applied successfully."
}

# Main Script Execution
main() {
    if [[ -z "$PROJECT_ID" || -z "$REGION" ]]; then
        log ERROR "Usage: ./apply-tf.sh <PROJECT_ID> <REGION>"
    fi

    check_auth_and_project
    apply_terraform
}

main "$@"
