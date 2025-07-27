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

# ✅ Wait until Crossplane CRDs are available
resource "null_resource" "wait_for_crds" {
  depends_on = [helm_release.crossplane]

  provisioner "local-exec" {
    command = <<EOT
for i in {1..30}; do
  kubectl get crd providers.pkg.crossplane.io >/dev/null 2>&1 && exit 0
  echo "Waiting for Crossplane CRDs..."
  sleep 5
done
echo "Timeout waiting for Crossplane CRDs" && exit 1
EOT
  }
}

# Crossplane AWS Provider Configuration
resource "kubernetes_manifest" "crossplane_aws_provider" {
  manifest = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name      = "provider-aws"
      namespace = "crossplane-system"
    }
    spec = {
      package = "xpkg.upbound.io/crossplane-contrib/provider-aws:v0.44.0"
    }
  }

  depends_on = [null_resource.wait_for_crds]
}

# Wait for AWS provider to be installed
resource "null_resource" "wait_for_provider" {
  depends_on = [kubernetes_manifest.crossplane_aws_provider]

  provisioner "local-exec" {
    command = <<EOT
for i in {1..30}; do
  kubectl get provider.pkg.crossplane.io provider-aws -n crossplane-system >/dev/null 2>&1 && exit 0
  echo "Waiting for Crossplane AWS provider to be available..."
  sleep 5
done
echo "Timeout waiting for provider-aws" && exit 1
EOT
  }
}

# Crossplane ProviderConfig for AWS
resource "kubernetes_manifest" "crossplane_aws_provider_config" {
  manifest = {
    apiVersion = "aws.crossplane.io/v1beta1"
    kind       = "ProviderConfig"
    metadata = {
      name = "default"
    }
    spec = {
      credentials = {
        source = "IRSA"
      }
    }
  }

  depends_on = [null_resource.wait_for_provider]
}