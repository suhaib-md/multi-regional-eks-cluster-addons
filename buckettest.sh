#!/bin/bash

CONTEXT="east"
REGION="us-east-1"

echo "🧪 Testing Crossplane S3 Bucket Creation (No ACL)"

# Create a simple bucket without ACL
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: crossplane-no-acl-$(date +%s)
spec:
  forProvider:
    region: us-east-1
    publicAccessBlockConfiguration:
      blockPublicAcls: true
      blockPublicPolicy: true
      ignorePublicAcls: true
      restrictPublicBuckets: true
  providerConfigRef:
    name: default
  deletionPolicy: Delete
EOF

# Wait and check status
sleep 30
kubectl --context $CONTEXT get buckets.s3.aws.crossplane.io