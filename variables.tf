variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "devops-poc"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "regions" {
  description = "List of AWS regions to deploy EKS clusters"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "cluster_version" {
  description = <<EOT
Kubernetes version for all EKS clusters.

If null, the latest available version per region will be determined dynamically 
(using an external data source or a local fallback).
EOT
  type    = string
  default = null
}

variable "node_groups" {
  description = "EKS node group configuration (shared across regions)"
  type = map(object({
    instance_types = list(string)
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
    disk_size = number
  }))
  default = {
    general = {
      instance_types = ["t3.medium"]
      scaling_config = {
        desired_size = 2
        max_size     = 4
        min_size     = 1
      }
      disk_size = 20
    }
  }
}

variable "vpc_cidr_blocks" {
  description = "CIDR blocks for VPCs in each region"
  type        = map(string)
  default = {
    "us-east-1" = "10.1.0.0/16"
    "us-west-2" = "10.2.0.0/16"
  }
}
