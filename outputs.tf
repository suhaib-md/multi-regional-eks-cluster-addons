output "cluster_endpoints" {
  description = "EKS cluster API server endpoints per region"
  value = {
    "us-east-1" = module.eks_us_east_1.cluster_endpoint
    "us-west-2" = module.eks_us_west_2.cluster_endpoint
  }
}

output "cluster_security_group_ids" {
  description = "Security group IDs attached to the EKS cluster per region"
  value = {
    "us-east-1" = module.eks_us_east_1.cluster_security_group_id
    "us-west-2" = module.eks_us_west_2.cluster_security_group_id
  }
}

output "cluster_names" {
  description = "EKS cluster names per region"
  value = {
    "us-east-1" = module.eks_us_east_1.cluster_name
    "us-west-2" = module.eks_us_west_2.cluster_name
  }
}

output "cluster_arns" {
  description = "EKS cluster ARNs per region"
  value = {
    "us-east-1" = module.eks_us_east_1.cluster_arn
    "us-west-2" = module.eks_us_west_2.cluster_arn
  }
}

output "cluster_versions" {
  description = "EKS Kubernetes versions per region"
  value = {
    "us-east-1" = module.eks_us_east_1.cluster_version
    "us-west-2" = module.eks_us_west_2.cluster_version
  }
}

output "vpc_ids" {
  description = "VPC IDs per region"
  value = {
    "us-east-1" = module.networking_us_east_1.vpc_id
    "us-west-2" = module.networking_us_west_2.vpc_id
  }
}
