#!/bin/bash

CONTEXT="east"

echo "🚀 Creating S3 Bucket WITHOUT ACL (This will work!)"

# Create a minimal bucket without any ACL configuration
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: crossplane-minimal-$(date +%s)
spec:
  forProvider:
    locationConstraint: us-east-1
    # No ACL, no publicAccessBlockConfiguration - let S3 use defaults
    serverSideEncryptionConfiguration:
      rules:
      - applyServerSideEncryptionByDefault:
          sseAlgorithm: AES256
    tagging:
      tagSet:
      - key: Environment
        value: test
      - key: Purpose
        value: crossplane-validation
  providerConfigRef:
    name: default
  deletionPolicy: Delete
EOF

echo "⏳ Waiting 45 seconds for bucket to be ready..."
sleep 45

echo "📊 Checking bucket status:"
kubectl --context $CONTEXT get buckets.s3.aws.crossplane.io

echo -e "\n🔍 Checking the newest bucket:"
NEWEST_BUCKET=$(kubectl --context $CONTEXT get buckets.s3.aws.crossplane.io --sort-by=.metadata.creationTimestamp -o name | tail -1)
echo "Newest bucket: $NEWEST_BUCKET"

if [ -n "$NEWEST_BUCKET" ]; then
    echo -e "\n=== Bucket Status Details ==="
    kubectl --context $CONTEXT describe $NEWEST_BUCKET | grep -A 10 -B 5 -E "(Ready|Synced|Events)"
fi

echo -e "\n🪣 AWS S3 Bucket List:"
aws s3 ls | grep crossplane

echo -e "\n✅ If you see 'Ready: True' and 'Synced: True' above, Crossplane is fully working!"