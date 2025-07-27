#!/bin/bash

CONTEXT="east"
REGION="us-east-1"
CLUSTER_NAME="devops-poc-prod-us-east-1"
ROLE_ARN="arn:aws:iam::096438464769:role/devops-poc-prod-crossplane-provider-aws-us-east-1"

echo "=== Comprehensive Fix for Crossplane Provider Issues ==="

echo "1. Delete the current failing provider to start fresh:"
kubectl --context $CONTEXT delete provider provider-aws -n crossplane-system --ignore-not-found=true

echo -e "\n2. Wait for cleanup:"
sleep 30

echo -e "\n3. Create the missing service account:"
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: provider-aws
  namespace: crossplane-system
  annotations:
    eks.amazonaws.com/role-arn: $ROLE_ARN
EOF

echo -e "\n4. Create comprehensive RBAC permissions:"
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: crossplane-provider-aws-comprehensive
rules:
# Core Kubernetes resources
- apiGroups: [""]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["apps"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["extensions"]
  resources: ["*"]
  verbs: ["*"]
# RBAC
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
# API Extensions
- apiGroups: ["apiextensions.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
# Crossplane Core
- apiGroups: ["crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["pkg.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
# AWS Crossplane Resources - Individual API Groups
- apiGroups: ["athena.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["route53resolver.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["ecr.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["dynamodb.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["s3.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["ec2.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["iam.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["rds.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["eks.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["lambda.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["sns.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["sqs.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["apigateway.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["apigatewayv2.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["batch.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["cloudformation.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["cloudfront.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["cloudtrail.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["cloudwatch.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["cloudwatchlogs.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["docdb.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["efs.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["elasticache.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["elbv2.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["kms.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["route53.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
# Catch-all for any other AWS resources
- apiGroups: ["*.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: crossplane-provider-aws-comprehensive
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: crossplane-provider-aws-comprehensive
subjects:
- kind: ServiceAccount
  name: provider-aws
  namespace: crossplane-system
EOF

echo -e "\n5. Create DeploymentRuntimeConfig:"
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: provider-aws-config
spec:
  deploymentTemplate:
    spec:
      selector: {}
      template:
        spec:
          serviceAccountName: provider-aws
          containers:
          - name: package-runtime
            env:
            - name: AWS_ROLE_ARN
              value: $ROLE_ARN
            - name: AWS_WEB_IDENTITY_TOKEN_FILE
              value: /var/run/secrets/eks.amazonaws.com/serviceaccount/token
            volumeMounts:
            - name: aws-iam-token
              mountPath: /var/run/secrets/eks.amazonaws.com/serviceaccount
              readOnly: true
          volumes:
          - name: aws-iam-token
            projected:
              sources:
              - serviceAccountToken:
                  audience: sts.amazonaws.com
                  expirationSeconds: 86400
                  path: token
  serviceAccountTemplate:
    metadata:
      annotations:
        eks.amazonaws.com/role-arn: $ROLE_ARN
EOF

echo -e "\n6. Wait for runtime config to be ready:"
sleep 15

echo -e "\n7. Create provider with runtime config reference:"
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
  namespace: crossplane-system
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-aws:v0.44.0
  runtimeConfigRef:
    apiVersion: pkg.crossplane.io/v1beta1
    kind: DeploymentRuntimeConfig
    name: provider-aws-config
EOF

echo -e "\n8. Monitor provider installation:"
echo "Waiting for provider to be installed and healthy..."
for i in $(seq 1 120); do
  INSTALLED=$(kubectl --context $CONTEXT get provider.pkg.crossplane.io provider-aws -n crossplane-system -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' 2>/dev/null || echo "False")
  HEALTHY=$(kubectl --context $CONTEXT get provider.pkg.crossplane.io provider-aws -n crossplane-system -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null || echo "False")
  
  echo "Status check $i/120 - Installed: $INSTALLED, Healthy: $HEALTHY"
  
  if [ "$INSTALLED" = "True" ] && [ "$HEALTHY" = "True" ]; then
    echo "AWS Provider is installed and healthy!"
    break
  fi
  
  # Show detailed status every 30 seconds
  remainder=$((i % 6))
  if [ $remainder -eq 0 ]; then
    echo "Provider pods status:"
    kubectl --context $CONTEXT get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws
    echo "Recent events:"
    kubectl --context $CONTEXT get events -n crossplane-system --sort-by='.lastTimestamp' | tail -5
  fi
  
  sleep 5
done

echo -e "\n9. Final status check:"
kubectl --context $CONTEXT get providers -n crossplane-system
kubectl --context $CONTEXT get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws

echo -e "\n10. Check provider pod logs:"
sleep 10
NEW_POD=$(kubectl --context $CONTEXT get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NEW_POD" ]; then
  echo "Logs from pod: $NEW_POD"
  kubectl --context $CONTEXT logs -n crossplane-system $NEW_POD --tail=20
else
  echo "No provider pod found"
fi

echo -e "\n11. Create ProviderConfig:"
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
EOF

echo -e "\n12. Test with a simple S3 bucket (optional):"
echo "Creating test S3 bucket..."
cat <<EOF | kubectl --context $CONTEXT apply -f -
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: test-crossplane-bucket-$(date +%s)
spec:
  forProvider:
    region: $REGION
  providerConfigRef:
    name: default
EOF

echo -e "\nSetup completed! The provider should now be working correctly."
echo "If you still see issues, check the pod logs and events for more details."
