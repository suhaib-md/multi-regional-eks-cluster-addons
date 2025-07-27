# modules/eks-addons/main.tf

# Data source to get the latest add-on versions
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "ebs_csi_driver" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

# IAM role for EBS CSI Driver
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.project_name}-${var.environment}-ebs-csi-driver-role-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"  
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${var.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Attach the required policy to EBS CSI Driver role
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

# IAM role for Crossplane AWS Provider
resource "aws_iam_role" "crossplane_provider_aws" {
  name = "${var.project_name}-${var.environment}-crossplane-provider-aws-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity" 
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${var.oidc_provider}:sub" = "system:serviceaccount:crossplane-system:provider-aws-*"
            "${var.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Attach PowerUserAccess policy (you may want to restrict this further)
resource "aws_iam_role_policy_attachment" "crossplane_provider_aws" {
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
  role       = aws_iam_role.crossplane_provider_aws.name
}

# Attach IAMFullAccess policy for Crossplane to manage IAM resources
resource "aws_iam_role_policy_attachment" "crossplane_provider_aws_iam" {
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
  role       = aws_iam_role.crossplane_provider_aws.name
}

# CoreDNS Add-on
resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  tags = var.tags
}

# VPC CNI Add-on (usually installed by default, but we'll manage it)
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  tags = var.tags
}

# Kube Proxy Add-on
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  tags = var.tags
}

# EBS CSI Driver Add-on
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi_driver.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_driver
  ]
  
  tags = var.tags
}

# Create namespace for NGINX Ingress
resource "kubernetes_namespace" "nginx_ingress" {
  metadata {
    name = "ingress-nginx"
    labels = {
      name = "ingress-nginx"
    }
  }

  depends_on = [aws_eks_addon.coredns]
}

# NGINX Ingress Controller using Helm
resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.8.3"
  namespace  = kubernetes_namespace.nginx_ingress.metadata[0].name

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-cross-zone-load-balancing-enabled"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.nginx_ingress,
    aws_eks_addon.ebs_csi_driver
  ]
}

# Create namespace for Crossplane
resource "kubernetes_namespace" "crossplane_system" {
  metadata {
    name = "crossplane-system"
    labels = {
      name = "crossplane-system"
    }
  }

  depends_on = [aws_eks_addon.coredns]
}

# Crossplane using Helm
resource "helm_release" "crossplane" {
  name       = "crossplane"
  repository = "https://charts.crossplane.io/stable"
  chart      = "crossplane"
  version    = "1.14.5"
  namespace  = kubernetes_namespace.crossplane_system.metadata[0].name

  set {
    name  = "resourcesCrossplane.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resourcesCrossplane.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "resourcesCrossplane.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resourcesCrossplane.requests.memory"
    value = "256Mi"
  }

  # ✅ Ensure Helm installs CRDs
  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.crossplane_system,
    aws_eks_addon.ebs_csi_driver
  ]
}

# Wait for Crossplane CRDs to be available
resource "time_sleep" "wait_for_crossplane_crds" {
  depends_on      = [helm_release.crossplane]
  create_duration = "60s"
}

# Create the provider-aws service account explicitly
resource "kubernetes_service_account" "crossplane_provider_aws" {
  metadata {
    name      = "provider-aws"
    namespace = kubernetes_namespace.crossplane_system.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.crossplane_provider_aws.arn
    }
  }

  depends_on = [time_sleep.wait_for_crossplane_crds]
}

# Create ClusterRole for Crossplane AWS Provider
resource "kubernetes_cluster_role" "crossplane_provider_aws" {
  metadata {
    name = "crossplane-provider-aws"
  }

  rule {
    api_groups = [""]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  # Crossplane core resources
  rule {
    api_groups = ["crossplane.io"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    api_groups = ["pkg.crossplane.io"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  # AWS Crossplane CRDs - comprehensive list
  rule {
    api_groups = [
      "athena.aws.crossplane.io",
      "route53resolver.aws.crossplane.io",
      "ecr.aws.crossplane.io",
      "dynamodb.aws.crossplane.io",
      "s3.aws.crossplane.io",
      "ec2.aws.crossplane.io",
      "iam.aws.crossplane.io",
      "rds.aws.crossplane.io",
      "eks.aws.crossplane.io",
      "lambda.aws.crossplane.io",
      "sns.aws.crossplane.io",
      "sqs.aws.crossplane.io",
      "apigateway.aws.crossplane.io",
      "apigatewayv2.aws.crossplane.io",
      "batch.aws.crossplane.io",
      "cloudformation.aws.crossplane.io",
      "cloudfront.aws.crossplane.io",
      "cloudtrail.aws.crossplane.io",
      "cloudwatch.aws.crossplane.io",
      "cloudwatchlogs.aws.crossplane.io",
      "docdb.aws.crossplane.io",
      "efs.aws.crossplane.io",
      "elasticache.aws.crossplane.io",
      "elbv2.aws.crossplane.io",
      "kms.aws.crossplane.io",
      "route53.aws.crossplane.io"
    ]
    resources = ["*"]
    verbs     = ["*"]
  }

  depends_on = [helm_release.crossplane]
}

# Create ClusterRoleBinding for Crossplane AWS Provider
resource "kubernetes_cluster_role_binding" "crossplane_provider_aws" {
  metadata {
    name = "crossplane-provider-aws"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.crossplane_provider_aws.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "provider-aws"
    namespace = kubernetes_namespace.crossplane_system.metadata[0].name
  }

  # Also bind to any provider-aws-* service accounts (for versioned providers)
  dynamic "subject" {
    for_each = ["provider-aws-1a98473eeed4"]
    content {
      kind      = "ServiceAccount"
      name      = subject.value
      namespace = kubernetes_namespace.crossplane_system.metadata[0].name
    }
  }

  depends_on = [helm_release.crossplane]
}

# Install Crossplane AWS Provider and configuration using kubectl
resource "null_resource" "install_crossplane_provider" {
  depends_on = [
    time_sleep.wait_for_crossplane_crds,
    kubernetes_service_account.crossplane_provider_aws,
    kubernetes_cluster_role.crossplane_provider_aws,
    kubernetes_cluster_role_binding.crossplane_provider_aws
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      # Update kubeconfig
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region} --kubeconfig /tmp/kubeconfig-${var.cluster_name}
      export KUBECONFIG=/tmp/kubeconfig-${var.cluster_name}

      # Wait for Crossplane CRDs to be available
      echo "Waiting for Crossplane CRDs to be available..."
      for i in $(seq 1 60); do
        if kubectl get crd providers.pkg.crossplane.io >/dev/null 2>&1; then
          echo "Provider CRDs are ready!"
          break
        fi
        echo "Waiting for Crossplane CRDs... ($i/60)"
        sleep 5
      done

      # Create additional RBAC for provider service accounts
      echo "Creating additional RBAC permissions..."
      cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: crossplane-provider-aws-extended
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps", "events", "serviceaccounts"]
  verbs: ["*"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apiextensions.k8s.io"]
  resources: ["customresourcedefinitions"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["clusterroles", "clusterrolebindings", "roles", "rolebindings"]
  verbs: ["*"]
- apiGroups: ["*.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["pkg.crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["crossplane.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: crossplane-provider-aws-extended
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: crossplane-provider-aws-extended
subjects:
- kind: ServiceAccount
  name: provider-aws
  namespace: crossplane-system
- kind: ServiceAccount
  name: provider-aws-1a98473eeed4
  namespace: crossplane-system
EOF

      # Install the AWS provider
      echo "Installing Crossplane AWS Provider..."
      cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
  namespace: crossplane-system
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-aws:v0.44.0
EOF

      # Wait for provider to be installed
      echo "Waiting for AWS provider to be ready..."
      for i in $(seq 1 180); do
        INSTALLED=$(kubectl get provider.pkg.crossplane.io provider-aws -n crossplane-system -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' 2>/dev/null || echo "False")
        HEALTHY=$(kubectl get provider.pkg.crossplane.io provider-aws -n crossplane-system -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null || echo "False")
        
        if [ "$INSTALLED" = "True" ] && [ "$HEALTHY" = "True" ]; then
          echo "AWS Provider is installed and healthy!"
          break
        fi
        
        echo "Waiting for AWS provider installation and health... ($i/180) - Installed: $INSTALLED, Healthy: $HEALTHY"
        
        # Show provider status for debugging
        remainder=$((i % 12))
        if [ $remainder -eq 0 ]; then
          echo "Provider status:"
          kubectl get provider.pkg.crossplane.io provider-aws -n crossplane-system -o yaml | grep -A 10 "status:" || true
        fi
        
        sleep 10
      done

      # Wait for DeploymentRuntimeConfig CRD to be available
      echo "Waiting for DeploymentRuntimeConfig CRD..."
      for i in $(seq 1 60); do
        if kubectl get crd deploymentruntimeconfigs.pkg.crossplane.io >/dev/null 2>&1; then
          echo "DeploymentRuntimeConfig CRD is ready!"
          break
        fi
        echo "Waiting for DeploymentRuntimeConfig CRD... ($i/60)"
        sleep 5
      done

      # Create DeploymentRuntimeConfig for IRSA
      echo "Creating DeploymentRuntimeConfig..."
      cat <<EOF | kubectl apply -f -
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
              value: ${aws_iam_role.crossplane_provider_aws.arn}
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
        eks.amazonaws.com/role-arn: ${aws_iam_role.crossplane_provider_aws.arn}
EOF

      # Wait a bit for the runtime config to be processed
      sleep 30

      # Update the provider to use the runtime config
      echo "Updating provider to use runtime config..."
      kubectl patch provider provider-aws -n crossplane-system --type='merge' -p='{"spec":{"runtimeConfigRef":{"apiVersion":"pkg.crossplane.io/v1beta1","kind":"DeploymentRuntimeConfig","name":"provider-aws-config"}}}'

      # Wait for provider to restart with new config
      echo "Waiting for provider deployment to restart..."
      sleep 60

      # Force restart the provider deployment if needed
      echo "Restarting provider deployment..."
      kubectl rollout restart deployment -l pkg.crossplane.io/provider=provider-aws -n crossplane-system || true
      
      # Wait for rollout to complete
      for i in $(seq 1 60); do
        if kubectl rollout status deployment -l pkg.crossplane.io/provider=provider-aws -n crossplane-system --timeout=10s >/dev/null 2>&1; then
          echo "Provider deployment restarted successfully!"
          break
        fi
        echo "Waiting for provider deployment restart... ($i/60)"
        sleep 10
      done

      # Create ProviderConfig
      echo "Creating ProviderConfig..."
      cat <<EOF | kubectl apply -f -
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
EOF

      # Final status check
      echo "Final provider status check..."
      kubectl get provider.pkg.crossplane.io provider-aws -n crossplane-system -o yaml
      echo "Provider deployments:"
      kubectl get deployments -n crossplane-system -l pkg.crossplane.io/provider=provider-aws
      echo "Provider pods:"
      kubectl get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws

      echo "Crossplane AWS Provider installation completed!"
    EOT
  }

  # Clean up kubeconfig on destroy
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f /tmp/kubeconfig-${self.triggers.cluster_name} || true"
  }

  # Trigger re-creation if cluster changes
  triggers = {
    cluster_name         = var.cluster_name
    region              = var.region
    crossplane_role_arn = aws_iam_role.crossplane_provider_aws.arn
    # Add a version trigger to force updates when needed
    provider_version    = "v0.44.0"
    # Add RBAC trigger
    rbac_version        = "v2"
  }
}