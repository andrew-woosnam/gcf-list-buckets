#!/bin/bash

# Variables
COMPUTE_PROJECT="proj-awoosnam"
TARGET_PROJECT="striped-device-445917-b7"
BUCKET_NAME="tickleface-gcs"
SERVICE_ACCOUNT="576375071060-compute@developer.gserviceaccount.com"
ACCESS_TOKEN=$(gcloud auth print-access-token)

# Check if billing is enabled for the compute project
echo "Step 1: Checking if billing is enabled for $COMPUTE_PROJECT..."
BILLING_ENABLED=$(gcloud beta billing projects describe "$COMPUTE_PROJECT" --format="value(billingEnabled)")
if [ "$BILLING_ENABLED" != "True" ]; then
    echo "ERROR: Billing is not enabled for $COMPUTE_PROJECT."
    exit 1
fi
echo "Billing is enabled for $COMPUTE_PROJECT."

# Print the ACCESS_TOKEN
echo "Step 2: Printing ACCESS_TOKEN for debugging..."
echo "Access Token: $ACCESS_TOKEN"
if [ -z "$ACCESS_TOKEN" ]; then
    echo "ERROR: ACCESS_TOKEN is empty. Ensure you are authenticated."
    exit 1
fi

# Test bucket access without `userProject`
echo "Step 3: Testing bucket access without userProject..."
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
     "https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME/o" -o response.json

if grep -q "401" response.json; then
    echo "Bucket access without userProject failed: 401 Unauthorized."
else
    echo "Bucket access without userProject succeeded."
fi

# Test bucket access with `proj-awoosnam` as userProject
echo "Step 4: Testing bucket access with $COMPUTE_PROJECT as userProject..."
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
     "https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME/o?userProject=$COMPUTE_PROJECT" -o response.json

if grep -q "401" response.json; then
    echo "Bucket access with $COMPUTE_PROJECT as userProject failed: 401 Unauthorized."
else
    echo "Bucket access with $COMPUTE_PROJECT as userProject succeeded."
fi

# Test bucket access with `striped-device-445917-b7` as userProject
echo "Step 5: Testing bucket access with $TARGET_PROJECT as userProject..."
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
     "https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME/o?userProject=$TARGET_PROJECT" -o response.json

if grep -q "401" response.json; then
    echo "Bucket access with $TARGET_PROJECT as userProject failed: 401 Unauthorized."
else
    echo "Bucket access with $TARGET_PROJECT as userProject succeeded."
fi

# Cleanup
rm -f response.json

echo "Diagnostics completed."
