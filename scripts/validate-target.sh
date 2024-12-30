#!/bin/bash

# Activate Target Project Configuration
echo "Activating Target Project Configuration..."
gcloud config configurations activate target-account
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to activate Target Project configuration."
    exit 1
fi

# Variables
TARGET_PROJECT="striped-device-445917-b7"
BUCKET_NAME="tickleface-gcs"
BUCKET="gs://$BUCKET_NAME"
SERVICE_ACCOUNT="576375071060-compute@developer.gserviceaccount.com"

# Validation
echo "Validating Target Project ($TARGET_PROJECT)..."
echo "Checking billing status..."
BILLING_STATUS=$(gcloud beta billing projects describe "$TARGET_PROJECT" --format="value(billingEnabled)")
if [ "$BILLING_STATUS" == "True" ]; then
    echo "Billing is enabled for project $TARGET_PROJECT."
else
    echo "Billing is NOT enabled for project $TARGET_PROJECT."
    exit 1
fi

echo "Checking IAM permissions for service account: $SERVICE_ACCOUNT on bucket: $BUCKET..."
POLICY=$(gcloud storage buckets get-iam-policy "$BUCKET" --format=json)
if echo "$POLICY" | grep -q "$SERVICE_ACCOUNT"; then
    echo "Service account $SERVICE_ACCOUNT has permissions on bucket $BUCKET."
else
    echo "Service account $SERVICE_ACCOUNT does NOT have permissions on bucket $BUCKET."
    exit 1
fi

echo "Target Project validation completed."
