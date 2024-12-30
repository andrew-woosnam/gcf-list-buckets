#!/bin/bash

# Activate Compute Project Configuration
echo "Activating Compute Project Configuration..."
gcloud config configurations activate compute-account
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to activate Compute Project configuration."
    exit 1
fi

# Variables
COMPUTE_PROJECT="proj-awoosnam"
BUCKET_NAME="tickleface-gcs"
BUCKET="gs://$BUCKET_NAME"

# Validation
echo "Validating Compute Project ($COMPUTE_PROJECT)..."
echo "Checking billing status..."
BILLING_STATUS=$(gcloud beta billing projects describe "$COMPUTE_PROJECT" --format="value(billingEnabled)")
if [ "$BILLING_STATUS" == "True" ]; then
    echo "Billing is enabled for project $COMPUTE_PROJECT."
else
    echo "Billing is NOT enabled for project $COMPUTE_PROJECT."
    exit 1
fi

echo "Testing bucket access for bucket $BUCKET with userProject $COMPUTE_PROJECT..."
ACCESS_TOKEN=$(gcloud auth print-access-token)
RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
     "https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME/o?userProject=$COMPUTE_PROJECT")
if echo "$RESPONSE" | grep -q "\"error\""; then
    echo "Bucket access failed."
    echo "Response: $RESPONSE"
else
    echo "Bucket access succeeded."
fi

echo "Compute Project validation completed."
