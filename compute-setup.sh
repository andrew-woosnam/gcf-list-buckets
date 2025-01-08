#!/bin/bash

# Script: compute-setup.sh
# Purpose: Ensure the correct GCP account, project, and ADC are active, then apply Terraform.

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
    REQUIRED_VARS=("COMPUTE_PROJECT_ID" "REGION" "COMPUTE_ACCT_USER_EMAIL")
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
    gcloud config set project "$COMPUTE_PROJECT_ID" || log ERROR "Failed to set project: $COMPUTE_PROJECT_ID."
    log SUCCESS "Authenticated and active project set to $COMPUTE_PROJECT_ID."
}

# Set Application Default Credentials (ADC)
setup_adc() {
    log INFO "Setting up Application Default Credentials (ADC)..."
    gcloud auth application-default login || log ERROR "Failed to set up ADC. Run 'gcloud auth application-default login' manually."
    log SUCCESS "Application Default Credentials set up successfully."
}

# Initialize and Apply Terraform
apply_terraform() {
    echo "[INFO] Initializing Terraform..."
    terraform init $TERRAFORM_INIT_OPTIONS

    echo "[INFO] Applying Terraform configuration..."
    terraform apply \
        -var="project_id=$COMPUTE_PROJECT_ID" \
        -var="region=$REGION" \
        -var="user_email=$COMPUTE_ACCT_USER_EMAIL" \
        -var="cloud_function_sa=$CLOUD_FUNCTION_SERVICE_ACCOUNT_NAME" \
        -var="cloud_func_name=$CLOUD_FUNC_NAME" \
        -var="go_runtime=$GO_RUNTIME" \
        -var="entry_point=$ENTRY_POINT" \
        -var="bucket_name=$BUCKET_NAME" \
        -auto-approve $TERRAFORM_APPLY_OPTIONS
}

# Main Script Execution
main() {
    load_env
    check_auth_and_project
    setup_adc
    apply_terraform
}

main "$@"
