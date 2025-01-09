#!/bin/bash

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

    log INFO "Loading configuration from config.env..."
    set -a
    source config.env
    set +a

    REQUIRED_VARS=(
        "COMPUTE_PROJECT_ID"
        "REGION"
        "GO_FUNC_FILE"
        "GO_MOD_FILE"
        "CLOUD_FUNC_NAME"
        "CLOUD_FUNCTION_SERVICE_ACCOUNT_NAME"
        "PUBSUB_TOPIC_ID"
        "PUBSUB_SUBSCRIPTION_ID"
    )

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

    if [[ -z "$active_account" ]]; then
        log ERROR "No active account detected. Please authenticate."
    fi

    if [[ "$active_account" != "$COMPUTE_ACCT_USER_EMAIL" ]]; then
        log INFO "Active account ($active_account) does not match the expected account ($COMPUTE_ACCT_USER_EMAIL)."
        log INFO "Switching to the correct account..."

        gcloud auth login "$COMPUTE_ACCT_USER_EMAIL" --brief || log ERROR "Failed to switch to the correct account: $COMPUTE_ACCT_USER_EMAIL."
        active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || echo "")

        if [[ "$active_account" != "$COMPUTE_ACCT_USER_EMAIL" ]]; then
            log ERROR "Failed to set the expected account: $COMPUTE_ACCT_USER_EMAIL."
        fi

        log SUCCESS "Switched to the correct account: $active_account."
    else
        log SUCCESS "Active account matches the expected account: $active_account."
    fi

    if [[ -z "$active_project" ]]; then
        log ERROR "No active project detected. Please set a project."
    fi

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

# Run Terraform to Configure GCP Resources
run_terraform() {
    log INFO "Running Terraform to configure GCP resources..."
    terraform init -input=false || log ERROR "Terraform initialization failed."
    terraform apply -auto-approve \
        -var="project_id=$COMPUTE_PROJECT_ID" \
        -var="region=$REGION" \
        -var="cloud_function_sa=$CLOUD_FUNCTION_SERVICE_ACCOUNT_NAME" \
        -var="pubsub_topic_id=$PUBSUB_TOPIC_ID" \
        -var="pubsub_subscription_id=$PUBSUB_SUBSCRIPTION_ID" \
        || log ERROR "Terraform apply failed."
    log SUCCESS "Terraform applied successfully."
}

# Validate Required IAM Permissions for Service Account
validate_iam_permissions() {
    log INFO "Validating IAM permissions for service account..."

    SERVICE_ACCOUNT_EMAIL="$CLOUD_FUNCTION_SERVICE_ACCOUNT_NAME@$COMPUTE_PROJECT_ID.iam.gserviceaccount.com"
    REQUIRED_ROLES=(
        "roles/logging.logWriter"
        "roles/pubsub.publisher"
        "roles/serviceusage.serviceUsageConsumer"
        "roles/storage.objectViewer" # Add any additional roles here
    )

    for role in "${REQUIRED_ROLES[@]}"; do
        log INFO "Checking if service account has role: $role"
        if gcloud projects get-iam-policy "$COMPUTE_PROJECT_ID" \
            --flatten="bindings[].members" \
            --filter="bindings.role:$role AND bindings.members:serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
            --format="value(bindings.role)" | grep -q "$role"; then
            log SUCCESS "Service account has role: $role"
        else
            log ERROR "Service account is missing role: $role. Ensure this role is assigned in your Terraform configuration."
        fi
    done

    log SUCCESS "All required IAM roles are validated for service account: $SERVICE_ACCOUNT_EMAIL"
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

    mkdir -p ./function
    cp "$GO_FUNC_FILE" ./function/main.go
    cp "$GO_MOD_FILE" ./function/go.mod

    SERVICE_ACCOUNT_EMAIL="$CLOUD_FUNCTION_SERVICE_ACCOUNT_NAME@$COMPUTE_PROJECT_ID.iam.gserviceaccount.com"

    gcloud functions deploy "$CLOUD_FUNC_NAME" \
        --region="$REGION" \
        --runtime="$GO_RUNTIME" \
        --entry-point="$ENTRY_POINT" \
        --source="./function" \
        --trigger-http \
        --gen2 \
        --service-account="$SERVICE_ACCOUNT_EMAIL" \
        --allow-unauthenticated \
        --update-env-vars="BUCKET_NAME=$BUCKET_NAME,COMPUTE_PROJECT_ID=$COMPUTE_PROJECT_ID,PUBSUB_TOPIC_ID=test-topic,PUBSUB_SUBSCRIPTION_ID=test-subscription,DEBUG=true,GOOGLE_API_GO_CLIENT_LOG=debug" || log ERROR "Failed to deploy/update Cloud Function."

    rm -rf ./function

    log SUCCESS "Cloud Function deployed successfully."
}

# Main Script Execution
main() {
    load_env
    check_auth_and_project
    setup_adc
    run_terraform
    deploy_cloud_function
    validate_iam_permissions
}

main "$@"
