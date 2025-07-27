#!/bin/bash

echo "=== Debugging Crossplane Provider CrashLoopBackOff ==="

CONTEXT="east"

echo "1. Check provider pod logs:"
kubectl --context $CONTEXT logs -n crossplane-system provider-aws-1a98473eeed4-769bb6b46f-sw754 --tail=50

echo -e "\n2. Check previous logs if pod restarted:"
kubectl --context $CONTEXT logs -n crossplane-system provider-aws-1a98473eeed4-769bb6b46f-sw754 --previous --tail=50

echo -e "\n3. Describe the failing pod:"
kubectl --context $CONTEXT describe pod -n crossplane-system provider-aws-1a98473eeed4-769bb6b46f-sw754

echo -e "\n4. Check deployment details:"
kubectl --context $CONTEXT describe deployment -n crossplane-system provider-aws-1a98473eeed4

echo -e "\n5. Check service account details:"
kubectl --context $CONTEXT describe serviceaccount -n crossplane-system provider-aws

echo -e "\n6. Check if service account has proper annotations:"
kubectl --context $CONTEXT get serviceaccount -n crossplane-system provider-aws -o yaml

echo -e "\n7. Check DeploymentRuntimeConfig:"
kubectl --context $CONTEXT get deploymentruntimeconfig -o yaml

echo -e "\n8. Check provider status:"
kubectl --context $CONTEXT get provider provider-aws -o yaml

echo -e "\n9. Check all pods in crossplane-system:"
kubectl --context $CONTEXT get pods -n crossplane-system -o wide

echo -e "\n10. Check events in crossplane-system namespace:"
kubectl --context $CONTEXT get events -n crossplane-system --sort-by='.lastTimestamp' | tail -20
