# modules/eks-addons/outputs.tf

output "coredns_addon_version" {
  description = "Version of the CoreDNS add-on"
  value       = aws_eks_addon.coredns.addon_version
}

output "ebs_csi_driver_addon_version" {
  description = "Version of the EBS CSI Driver add-on"
  value       = aws_eks_addon.ebs_csi_driver.addon_version
}

output "nginx_ingress_namespace" {
  description = "Namespace where NGINX Ingress is deployed"
  value       = kubernetes_namespace.nginx_ingress.metadata[0].name
}

output "crossplane_namespace" {
  description = "Namespace where Crossplane is deployed"
  value       = kubernetes_namespace.crossplane_system.metadata[0].name
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the IAM role used by EBS CSI Driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "crossplane_provider_role_arn" {
  description = "ARN of the IAM role used by Crossplane AWS Provider"
  value       = aws_iam_role.crossplane_provider_aws.arn
}