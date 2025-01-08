#!/bin/bash

# Script: compute-setup.sh
# Purpose: Ensure the correct GCP account, project, and ADC are active, and deploy a Cloud Function directly using gcloud.

set -euo pipefail

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

# Load Configuration from config.env
load_env() {
    if [[ ! -f config.env ]]; then
        log ERROR "Missing config.env file. Please create one with required variables."
    fi

    # Source the environment variables from config.env
    log INFO "Loading configuration from config.env..."
    set -a
    source config.env
    set +a

    # Check required variables
    REQUIRED_VARS=("COMPUTE_PROJECT_ID" "REGION" "GO_FUNC_FILE" "GO_MOD_FILE" "CLOUD_FUNC_NAME")
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log ERROR "Missing required variable $var in config.env."
        fi
    done

    log SUCCESS "Configuration loaded successfully."
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

    if [[ "$active_project" != "$COMPUTE_PROJECT_ID" ]]; then
        log INFO "Active project ($active_project) does not match the expected project ($COMPUTE_PROJECT_ID)."
        gcloud config set project "$COMPUTE_PROJECT_ID" || log ERROR "Failed to set project: $COMPUTE_PROJECT_ID."
    fi

    log SUCCESS "Authentication and project match verified."
}

# Check and Set Application Default Credentials (ADC)
setup_adc() {
    log INFO "Checking Application Default Credentials (ADC)..."

    # Verify if ADC is already set and valid
    if gcloud auth application-default print-access-token &>/dev/null; then
        log SUCCESS "Application Default Credentials are already set and valid."
    else
        log INFO "Setting up Application Default Credentials (ADC)..."
        gcloud auth application-default login || log ERROR "Failed to set up ADC. Run 'gcloud auth application-default login' manually."
        log SUCCESS "Application Default Credentials set up successfully."
    fi
}

# Deploy Cloud Function
deploy_cloud_function() {
    log INFO "Deploying Cloud Function directly using gcloud..."

    if [[ ! -f "$GO_FUNC_FILE" ]]; then
        log ERROR "Go function file not found: $GO_FUNC_FILE."
    fi

    if [[ ! -f "$GO_MOD_FILE" ]]; then
        log ERROR "Go mod file not found: $GO_MOD_FILE."
    fi

    # Prepare deployment directory
    mkdir -p ./function
    cp "$GO_FUNC_FILE" ./function/main.go
    cp "$GO_MOD_FILE" ./function/go.mod

    # Deploy the Cloud Function
    gcloud functions deploy "$CLOUD_FUNC_NAME" \
        --region="$REGION" \
        --runtime="go122" \
        --entry-point="ListBucketObjects" \
        --source="./function" \
        --trigger-http \
        --allow-unauthenticated \
        --update-env-vars="COMPUTE_PROJECT_ID=$COMPUTE_PROJECT_ID" || log ERROR "Failed to deploy Cloud Function."

    rm -rf ./function
    log SUCCESS "Cloud Function deployed successfully."
}

# Main Script Execution
main() {
    load_env
    check_auth_and_project
    setup_adc
    deploy_cloud_function
}

main "$@"
