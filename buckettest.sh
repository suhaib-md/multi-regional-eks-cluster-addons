#!/bin/bash

CONTEXT="east"

echo "🚀 Creating S3 Bucket with proper Crossplane configuration"

# Create a bucket with correct Crossplane API fields
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: crossplane-fixed-$(date +%s)
spec:
  forProvider:
    locationConstraint: us-east-1
    # Disable ACL management to avoid MissingSecurityHeader errors
    objectOwnership: BucketOwnerEnforced
    # Enable public access block (recommended security practice)
    publicAccessBlockConfiguration:
      blockPublicAcls: true
      blockPublicPolicy: true
      ignorePublicAcls: true
      restrictPublicBuckets: true
    # Server-side encryption
    serverSideEncryptionConfiguration:
      rules:
      - applyServerSideEncryptionByDefault:
          sseAlgorithm: AES256
        bucketKeyEnabled: true
    # Tags
    tagging:
      tagSet:
      - key: Environment
        value: test
      - key: Purpose
        value: crossplane-validation
      - key: CreatedBy
        value: terraform-crossplane
  providerConfigRef:
    name: default
  deletionPolicy: Delete
EOF

echo "⏳ Waiting 60 seconds for bucket to be ready..."
sleep 60

echo "📊 Checking bucket status:"
kubectl --context $CONTEXT get buckets.s3.aws.crossplane.io

echo -e "\n🔍 Checking the newest bucket:"
NEWEST_BUCKET=$(kubectl --context $CONTEXT get buckets.s3.aws.crossplane.io --sort-by=.metadata.creationTimestamp -o name | tail -1)
echo "Newest bucket: $NEWEST_BUCKET"

if [ -n "$NEWEST_BUCKET" ]; then
    echo -e "\n=== Bucket Status Details ==="
    kubectl --context $CONTEXT describe $NEWEST_BUCKET
fi

echo -e "\n🪣 AWS S3 Bucket List:"
aws s3 ls | grep crossplane

echo -e "\n🧪 Testing bucket functionality:"
BUCKET_NAME=$(kubectl --context $CONTEXT get $NEWEST_BUCKET -o jsonpath='{.metadata.name}' 2>/dev/null)
if [ -n "$BUCKET_NAME" ]; then
    echo "Bucket resource name: $BUCKET_NAME"
    # Try to get the actual S3 bucket name from status
    ACTUAL_BUCKET=$(kubectl --context $CONTEXT get $NEWEST_BUCKET -o jsonpath='{.status.atProvider.arn}' 2>/dev/null | sed 's/.*://' 2>/dev/null)
    if [ -n "$ACTUAL_BUCKET" ]; then
        echo "Testing file upload to bucket: $ACTUAL_BUCKET"
        echo "test content" > /tmp/test-file.txt
        if aws s3 cp /tmp/test-file.txt s3://$ACTUAL_BUCKET/test-file.txt 2>/dev/null; then
            echo "✅ File upload successful!"
            aws s3 rm s3://$ACTUAL_BUCKET/test-file.txt 2>/dev/null
            echo "✅ File cleanup successful!"
        else
            echo "❌ File upload failed - bucket may not be ready yet"
        fi
        rm -f /tmp/test-file.txt
    fi
fi

echo -e "\n✅ If you see 'Ready: True' and 'Synced: True' above, Crossplane is fully working!"
echo "✅ The key changes made:"
echo "   - Set objectOwnership: BucketOwnerEnforced (disables ACLs)"
echo "   - Added publicAccessBlockConfiguration for security"
echo "   - Removed versioning (use separate BucketVersioning resource if needed)"
echo "   - Used correct 'locationConstraint' field"