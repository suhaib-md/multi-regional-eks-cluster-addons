#!/bin/bash

# Simple test for Crossplane S3 bucket creation
CONTEXT="east"
REGION="us-east-1"
BUCKET_NAME="crossplane-test-$(date +%s)"

echo "=== Simple Crossplane S3 Test ==="

echo "1. Current provider status:"
kubectl --context $CONTEXT get providers -n crossplane-system

echo -e "\n2. Checking if S3 CRDs are available:"
kubectl --context $CONTEXT get crd | grep s3.aws

echo -e "\n3. Creating test S3 bucket: $BUCKET_NAME"
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: $BUCKET_NAME
spec:
  forProvider:
    region: $REGION
    tags:
      Environment: test
      CreatedBy: crossplane
      Purpose: testing
  providerConfigRef:
    name: default
  deletionPolicy: Delete
EOF

echo -e "\n4. Waiting for bucket creation (this may take 2-3 minutes)..."
sleep 30

echo -e "\n5. Checking bucket status:"
kubectl --context $CONTEXT get bucket $BUCKET_NAME

echo -e "\n6. Detailed bucket information:"
kubectl --context $CONTEXT describe bucket $BUCKET_NAME

echo -e "\n7. Waiting a bit more and checking status again..."
sleep 60

kubectl --context $CONTEXT get bucket $BUCKET_NAME -o yaml | grep -A 20 "status:"

echo -e "\n8. Checking if bucket was created in AWS:"
# Get the actual bucket name from the status
AWS_BUCKET_NAME=$(kubectl --context $CONTEXT get bucket $BUCKET_NAME -o jsonpath='{.metadata.annotations.crossplane\.io/external-name}' 2>/dev/null)

if [ -n "$AWS_BUCKET_NAME" ]; then
    echo "AWS Bucket Name: $AWS_BUCKET_NAME"
    aws s3 ls "s3://$AWS_BUCKET_NAME" --region $REGION 2>/dev/null && echo "✅ Bucket found in AWS!" || echo "Checking AWS S3 list..."
    aws s3api head-bucket --bucket "$AWS_BUCKET_NAME" --region $REGION 2>/dev/null && echo "✅ Bucket accessible via API!" || echo "Bucket not yet accessible"
else
    echo "Trying alternative method to get bucket name..."
    kubectl --context $CONTEXT get bucket $BUCKET_NAME -o jsonpath='{.status.atProvider.arn}' 2>/dev/null
fi

echo -e "\n9. All S3 buckets in AWS (to verify):"
aws s3 ls --region $REGION | grep crossplane || echo "No crossplane buckets found yet"

echo -e "\n10. Cleanup - deleting test bucket:"
kubectl --context $CONTEXT delete bucket $BUCKET_NAME

echo -e "\nTest completed. If the bucket showed as 'Ready' or you saw it in AWS, Crossplane is working correctly!"