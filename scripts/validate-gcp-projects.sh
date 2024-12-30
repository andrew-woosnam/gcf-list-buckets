#!/bin/bash

# Configuration Variables
TARGET_PROJECT="striped-device-445917-b7"
COMPUTE_PROJECT="proj-awoosnam"
BUCKET_NAME="gs://tickleface-gcs"
SERVICE_ACCOUNT="576375071060-compute@developer.gserviceaccount.com"
SERVICE_ACCOUNT_KEY="proj-awoosnam-59c876929e82.json"
TARGET_CONFIG="target-account"
COMPUTE_CONFIG="compute-account"

# Function to activate a configuration
activate_config() {
    local config_name=$1
    echo "Activating configuration: $config_name..."
    gcloud config configurations activate "$config_name"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to activate configuration $config_name."
        exit 1
    fi
}

# Function to check IAM permissions for the service account
check_iam_permissions() {
    local project=$1
    echo "Checking IAM permissions for service account $SERVICE_ACCOUNT in project $project..."
    PROJECT_POLICY=$(gcloud projects get-iam-policy "$project" --format=json)
    if echo "$PROJECT_POLICY" | grep -q "$SERVICE_ACCOUNT"; then
        echo "Service account $SERVICE_ACCOUNT has permissions in project $project."
    else
        echo "ERROR: Service account $SERVICE_ACCOUNT does NOT have permissions in project $project."
    fi
}

# Function to check bucket-level IAM permissions
check_bucket_iam_permissions() {
    echo "Checking IAM permissions for service account $SERVICE_ACCOUNT on bucket $BUCKET_NAME..."
    BUCKET_POLICY=$(gcloud storage buckets get-iam-policy "$BUCKET_NAME" --format=json)
    if echo "$BUCKET_POLICY" | grep -q "$SERVICE_ACCOUNT"; then
        echo "Service account $SERVICE_ACCOUNT has permissions on bucket $BUCKET_NAME."
    else
        echo "ERROR: Service account $SERVICE_ACCOUNT does NOT have permissions on bucket $BUCKET_NAME."
    fi
}

# Function to check billing status
check_billing_status() {
    local project=$1
    echo "Checking billing status for project: $project..."
    BILLING_STATUS=$(gcloud beta billing projects describe "$project" --format="value(billingEnabled)")
    if [ "$BILLING_STATUS" == "True" ]; then
        echo "Billing is enabled for project $project."
    else
        echo "ERROR: Billing is NOT enabled for project $project."
        exit 1
    fi
}

# Function to test bucket access with userProject
test_bucket_access() {
    local user_project=$1
    echo "Testing bucket access for bucket $BUCKET_NAME with userProject $user_project..."
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
         "https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME/o?userProject=$user_project" -o response.json

    if grep -q "403" response.json; then
        echo "Bucket access failed."
        cat response.json
    else
        echo "Bucket access succeeded."
        cat response.json
    fi
    rm -f response.json
}

# Validate Target Project
activate_config "$TARGET_CONFIG"
check_iam_permissions "$TARGET_PROJECT"
check_bucket_iam_permissions

# Validate Compute Project
activate_config "$COMPUTE_CONFIG"
check_billing_status "$COMPUTE_PROJECT"

# Authenticate as the service account for Compute Project
echo "Activating service account for Compute Project..."
gcloud auth activate-service-account "$SERVICE_ACCOUNT" --key-file="$SERVICE_ACCOUNT_KEY" --project="$COMPUTE_PROJECT"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to activate service account $SERVICE_ACCOUNT for Compute Project."
    exit 1
fi

# Generate access token for the service account
ACCESS_TOKEN=$(gcloud auth print-access-token)
if [ -z "$ACCESS_TOKEN" ]; then
    echo "ERROR: Failed to generate access token."
    exit 1
fi

# Test bucket access for Compute Project
test_bucket_access "$COMPUTE_PROJECT"

echo "Validation completed successfully."
