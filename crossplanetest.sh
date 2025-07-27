#!/bin/bash

# Crossplane S3 Bucket Test Script
set -e

CONTEXTS=("east" "west")
TIMESTAMP=$(date +%s)

echo "Testing Crossplane S3 bucket creation across regions..."

for CONTEXT in "${CONTEXTS[@]}"; do
    echo "----------------------------------------"
    echo "Testing in context: $CONTEXT"
    echo "----------------------------------------"
    
    # Create a simple S3 bucket
    BUCKET_NAME="crossplane-test-bucket-${CONTEXT}-${TIMESTAMP}"
    
    cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: $BUCKET_NAME
spec:
  forProvider:
    acl: private
  providerConfigRef:
    name: default
  deletionPolicy: Delete
EOF

    echo "Created bucket: $BUCKET_NAME in context: $CONTEXT"
    
    # Wait a moment for the resource to be created
    echo "Waiting for bucket to be ready..."
    sleep 10
    
    # Check the status
    echo "Checking bucket status..."
    kubectl --context $CONTEXT get bucket $BUCKET_NAME -o yaml
    
    echo "Checking bucket conditions..."
    kubectl --context $CONTEXT describe bucket $BUCKET_NAME
    
    echo "----------------------------------------"
done

echo ""
echo "To monitor the buckets, you can run:"
echo "kubectl --context east get buckets"
echo "kubectl --context west get buckets"
echo ""
echo "To check events:"
echo "kubectl --context east get events --sort-by='.lastTimestamp'"
echo "kubectl --context west get events --sort-by='.lastTimestamp'"
echo ""
echo "To clean up, delete the buckets:"
echo "kubectl --context east delete buckets --all"
echo "kubectl --context west delete buckets --all"
