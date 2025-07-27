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
        Action = "sts:AssumeRole"
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
        Action = "sts:AssumeRole"
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

# Wait for Crossplane to be ready and then install AWS Provider via kubectl
resource "null_resource" "install_crossplane_provider" {
  depends_on = [helm_release.crossplane]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for Crossplane CRDs to be available
      for i in {1..60}; do
        if aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region} --kubeconfig /tmp/kubeconfig-${var.cluster_name}; then
          export KUBECONFIG=/tmp/kubeconfig-${var.cluster_name}
          if kubectl get crd providers.pkg.crossplane.io >/dev/null 2>&1; then
            echo "CRDs are ready, installing provider..."
            break
          fi
        fi
        echo "Waiting for Crossplane CRDs to be available... ($i/60)"
        sleep 10
      done

      # Create the provider
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
      for i in {1..30}; do
        if kubectl get provider.pkg.crossplane.io provider-aws -n crossplane-system -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' | grep -q "True"; then
          echo "AWS Provider is ready!"
          break
        fi
        echo "Waiting for AWS provider installation... ($i/30)"
        sleep 10
      done
    EOT
  }

  # Clean up kubeconfig on destroy
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f /tmp/kubeconfig-${self.triggers.cluster_name} || true"
  }

  # Trigger re-creation if cluster changes
  triggers = {
    cluster_name = var.cluster_name
    region       = var.region
  }
}

# Wait a bit more to ensure provider is fully ready
resource "time_sleep" "wait_for_provider_ready" {
  depends_on      = [null_resource.install_crossplane_provider]
  create_duration = "30s"
}

# Create ProviderConfig using kubectl to avoid API timing issues
resource "null_resource" "create_provider_config" {
  depends_on = [time_sleep.wait_for_provider_ready]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=/tmp/kubeconfig-${self.triggers.cluster_name}
      
      # First create a ControllerConfig for IRSA
      cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1alpha1
kind: ControllerConfig
metadata:
  name: aws-controller-config
spec:
  serviceAccountName: provider-aws
  annotations:
    eks.amazonaws.com/role-arn: ${self.triggers.crossplane_role_arn}
EOF

      # Wait a bit for the ControllerConfig to be processed
      sleep 10
      
      # Update the Provider to use the ControllerConfig
      kubectl patch provider.pkg.crossplane.io provider-aws -n crossplane-system --type merge -p '{"spec":{"controllerConfigRef":{"name":"aws-controller-config"}}}'
      
      # Wait for provider to restart with new config
      sleep 30
      
      # Create ProviderConfig with InjectedIdentity
      cat <<EOF | kubectl apply -f -
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
EOF
    EOT
  }

  # Trigger re-creation if cluster changes
  triggers = {
    cluster_name         = var.cluster_name
    region              = var.region
    crossplane_role_arn = aws_iam_role.crossplane_provider_aws.arn
  }
}