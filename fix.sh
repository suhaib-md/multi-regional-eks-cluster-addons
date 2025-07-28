#!/bin/bash

CONTEXT="east"
REGION="us-east-1"

echo "=== Corrected Crossplane Fix ==="

echo "1. Checking what resources actually exist:"
kubectl --context $CONTEXT get providers -n crossplane-system
kubectl --context $CONTEXT get deployments -n crossplane-system
kubectl --context $CONTEXT get pods -n crossplane-system

echo -e "\n2. Finding the correct provider resource:"
PROVIDER_NAME=$(kubectl --context $CONTEXT get providers -n crossplane-system -o name | grep provider-aws)
echo "Found provider: $PROVIDER_NAME"

echo -e "\n3. Getting provider revision correctly:"
PROVIDER_REVISION=$(kubectl --context $CONTEXT get $PROVIDER_NAME -n crossplane-system -o jsonpath='{.status.currentRevision}')
echo "Provider Revision: $PROVIDER_REVISION"

echo -e "\n4. Checking what type of workload is running the provider:"
kubectl --context $CONTEXT get all -n crossplane-system -l pkg.crossplane.io/provider=provider-aws

echo -e "\n5. Let's check the ProviderConfig schema:"
kubectl --context $CONTEXT explain providerconfig.spec --recursive | head -20

echo -e "\n6. Let's see what the current ProviderConfig looks like:"
kubectl --context $CONTEXT get providerconfig default -o yaml

echo -e "\n7. Creating a proper ProviderConfig without region field:"
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default-with-region
spec:
  credentials:
    source: InjectedIdentity
EOF

echo -e "\n8. Let's try to restart the provider pod directly:"
PROVIDER_POD=$(kubectl --context $CONTEXT get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws -o name)
echo "Restarting provider pod: $PROVIDER_POD"
kubectl --context $CONTEXT delete $PROVIDER_POD -n crossplane-system

echo -e "\n9. Waiting for pod to restart:"
sleep 30

echo -e "\n10. Checking new pod status:"
kubectl --context $CONTEXT get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws

echo -e "\n11. Testing with AWS CLI from provider pod:"
NEW_POD=$(kubectl --context $CONTEXT get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws -o name | head -1)
echo "Testing AWS access in pod: $NEW_POD"
kubectl --context $CONTEXT exec -n crossplane-system $NEW_POD -- aws sts get-caller-identity 2>/dev/null || echo "AWS CLI test failed"

echo -e "\n12. Check provider logs for any remaining errors:"
kubectl --context $CONTEXT logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws --tail=10

echo -e "\nFix completed!"