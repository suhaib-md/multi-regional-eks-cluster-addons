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

# IAM role for Crossplane AWS Provider with comprehensive permissions for S3 and other AWS services
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
            "${var.oidc_provider}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${var.oidc_provider}:sub" = [
              "system:serviceaccount:crossplane-system:provider-aws*"
            ]
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Custom IAM policy for Crossplane with all necessary permissions for S3 and other services
resource "aws_iam_policy" "crossplane_provider_aws" {
  name        = "${var.project_name}-${var.environment}-crossplane-provider-aws-${var.region}"
  description = "IAM policy for Crossplane AWS Provider with comprehensive permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Full Access
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
      },
      # EC2 Permissions
      {
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      # IAM Permissions (needed for role creation and management)
      {
        Effect = "Allow"
        Action = [
          "iam:*"
        ]
        Resource = "*"
      },
      # RDS Permissions
      {
        Effect = "Allow"
        Action = [
          "rds:*"
        ]
        Resource = "*"
      },
      # EKS Permissions
      {
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "*"
      },
      # Lambda Permissions
      {
        Effect = "Allow"
        Action = [
          "lambda:*"
        ]
        Resource = "*"
      },
      # CloudFormation Permissions
      {
        Effect = "Allow"
        Action = [
          "cloudformation:*"
        ]
        Resource = "*"
      },
      # SNS and SQS Permissions
      {
        Effect = "Allow"
        Action = [
          "sns:*",
          "sqs:*"
        ]
        Resource = "*"
      },
      # API Gateway Permissions
      {
        Effect = "Allow"
        Action = [
          "apigateway:*"
        ]
        Resource = "*"
      },
      # Route53 Permissions
      {
        Effect = "Allow"
        Action = [
          "route53:*",
          "route53resolver:*"
        ]
        Resource = "*"
      },
      # CloudWatch Permissions
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:*",
          "logs:*"
        ]
        Resource = "*"
      },
      # KMS Permissions
      {
        Effect = "Allow"
        Action = [
          "kms:*"
        ]
        Resource = "*"
      },
      # ElastiCache Permissions
      {
        Effect = "Allow"
        Action = [
          "elasticache:*"
        ]
        Resource = "*"
      },
      # ELB Permissions
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      },
      # DynamoDB Permissions
      {
        Effect = "Allow"
        Action = [
          "dynamodb:*"
        ]
        Resource = "*"
      },
      # ECR Permissions
      {
        Effect = "Allow"
        Action = [
          "ecr:*"
        ]
        Resource = "*"
      },
      # EFS Permissions
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:*"
        ]
        Resource = "*"
      },
      # SSM Permissions
      {
        Effect = "Allow"
        Action = [
          "ssm:*"
        ]
        Resource = "*"
      },
      # STS Permissions (for assuming roles)
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Attach the custom policy to Crossplane role
resource "aws_iam_role_policy_attachment" "crossplane_provider_aws_custom" {
  policy_arn = aws_iam_policy.crossplane_provider_aws.arn
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

# VPC CNI Add-on
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

  # Add timeout and retry configurations
  timeout          = 600
  cleanup_on_fail  = true
  wait             = true
  wait_for_jobs    = true

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

  # Add timeout and retry configurations
  timeout          = 600
  cleanup_on_fail  = true
  wait             = true
  wait_for_jobs    = true

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

  depends_on = [
    kubernetes_namespace.crossplane_system,
    aws_eks_addon.ebs_csi_driver
  ]
}

# Install Crossplane Provider and configuration using kubectl
resource "null_resource" "install_crossplane_provider" {
  depends_on = [
    helm_release.crossplane,
    aws_iam_role.crossplane_provider_aws,
    aws_iam_role_policy_attachment.crossplane_provider_aws_custom
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      # Update kubeconfig
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region} --kubeconfig /tmp/kubeconfig-${var.cluster_name}
      export KUBECONFIG=/tmp/kubeconfig-${var.cluster_name}

      # Wait for Crossplane CRDs to be available
      echo "Waiting for Crossplane CRDs to be available..."
      for i in $(seq 1 120); do
        if kubectl get crd providers.pkg.crossplane.io >/dev/null 2>&1; then
          echo "Provider CRDs are ready!"
          break
        fi
        echo "Waiting for Crossplane CRDs... ($i/120)"
        sleep 5
      done

      # Verify CRDs are ready
      if ! kubectl get crd providers.pkg.crossplane.io >/dev/null 2>&1; then
        echo "ERROR: Provider CRDs are not available after waiting"
        exit 1
      fi

      # Create ServiceAccount for the provider
      echo "Creating ServiceAccount for provider..."
      cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: provider-aws
  namespace: crossplane-system
  annotations:
    eks.amazonaws.com/role-arn: ${aws_iam_role.crossplane_provider_aws.arn}
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
  package: xpkg.upbound.io/crossplane-contrib/provider-aws:v0.49.0
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
        
        # Show provider status for debugging every 30 seconds
        remainder=$((i % 6))
        if [ $remainder -eq 0 ]; then
          echo "Provider status:"
          kubectl get provider.pkg.crossplane.io provider-aws -n crossplane-system -o wide || true
          echo "Provider pods:"
          kubectl get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws || true
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

      # Wait for AWS CRDs to be available
      echo "Waiting for AWS CRDs to be available..."
      for i in $(seq 1 120); do
        if kubectl get crd buckets.s3.aws.crossplane.io >/dev/null 2>&1; then
          echo "AWS S3 CRDs are ready!"
          break
        fi
        echo "Waiting for AWS S3 CRDs... ($i/120)"
        sleep 5
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
      kubectl get provider.pkg.crossplane.io provider-aws -n crossplane-system -o wide
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
    provider_version    = "v0.49.0"
    # Add RBAC trigger
    rbac_version        = "v3"
  }
}