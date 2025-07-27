provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}

# Fetch latest EKS version dynamically using external script
data "external" "eks_version_us_east_1" {
  program = ["python3", "${path.module}/scripts/get_latest_eks_version.py"]

  query = {
    region = "us-east-1"
  }
}

data "external" "eks_version_us_west_2" {
  program = ["python3", "${path.module}/scripts/get_latest_eks_version.py"]

  query = {
    region = "us-west-2"
  }
}

locals {
  cluster_versions = {
    "us-east-1" = var.cluster_version != null ? var.cluster_version : data.external.eks_version_us_east_1.result["latest_version"]
    "us-west-2" = var.cluster_version != null ? var.cluster_version : data.external.eks_version_us_west_2.result["latest_version"]
  }
}

# Create VPC and networking for us-east-1
module "networking_us_east_1" {
  source = "./modules/networking"

  providers = {
    aws = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  region       = "us-east-1"
  vpc_cidr     = var.vpc_cidr_blocks["us-east-1"]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Region      = "us-east-1"
  }
}

# Create VPC and networking for us-west-2
module "networking_us_west_2" {
  source = "./modules/networking"

  providers = {
    aws = aws.us_west_2
  }

  project_name = var.project_name
  environment  = var.environment
  region       = "us-west-2"
  vpc_cidr     = var.vpc_cidr_blocks["us-west-2"]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Region      = "us-west-2"
  }
}

# Create EKS cluster in us-east-1
module "eks_us_east_1" {
  source = "./modules/eks"

  providers = {
    aws = aws.us_east_1
  }

  project_name     = var.project_name
  environment      = var.environment
  region           = "us-east-1"
  cluster_version  = local.cluster_versions["us-east-1"]

  vpc_id                   = module.networking_us_east_1.vpc_id
  subnet_ids               = module.networking_us_east_1.private_subnet_ids
  control_plane_subnet_ids = module.networking_us_east_1.public_subnet_ids

  node_groups = var.node_groups

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Region      = "us-east-1"
  }

  depends_on = [module.networking_us_east_1]
}

# Create EKS cluster in us-west-2
module "eks_us_west_2" {
  source = "./modules/eks"

  providers = {
    aws = aws.us_west_2
  }

  project_name     = var.project_name
  environment      = var.environment
  region           = "us-west-2"
  cluster_version  = local.cluster_versions["us-west-2"]

  vpc_id                   = module.networking_us_west_2.vpc_id
  subnet_ids               = module.networking_us_west_2.private_subnet_ids
  control_plane_subnet_ids = module.networking_us_west_2.public_subnet_ids

  node_groups = var.node_groups

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Region      = "us-west-2"
  }

  depends_on = [module.networking_us_west_2]
}

# Install add-ons on us-east-1 cluster
module "eks_addons_us_east_1" {
  source = "./modules/eks-addons"

  providers = {
    aws        = aws.us_east_1
    helm       = helm.us_east_1
    kubernetes = kubernetes.us_east_1
  }

  project_name     = var.project_name
  environment      = var.environment
  region           = "us-east-1"
  cluster_name     = module.eks_us_east_1.cluster_name
  cluster_endpoint = module.eks_us_east_1.cluster_endpoint
  cluster_version  = module.eks_us_east_1.cluster_version
  cluster_certificate_authority_data = module.eks_us_east_1.cluster_certificate_authority_data
  oidc_provider_arn = module.eks_us_east_1.oidc_provider_arn
  oidc_provider     = module.eks_us_east_1.oidc_provider

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Region      = "us-east-1"
  }

  depends_on = [module.eks_us_east_1]
}

# Install add-ons on us-west-2 cluster
module "eks_addons_us_west_2" {
  source = "./modules/eks-addons"

  providers = {
    aws        = aws.us_west_2
    helm       = helm.us_west_2
    kubernetes = kubernetes.us_west_2
  }

  project_name     = var.project_name
  environment      = var.environment
  region           = "us-west-2"
  cluster_name     = module.eks_us_west_2.cluster_name
  cluster_endpoint = module.eks_us_west_2.cluster_endpoint
  cluster_version  = module.eks_us_west_2.cluster_version
  cluster_certificate_authority_data = module.eks_us_west_2.cluster_certificate_authority_data
  oidc_provider_arn = module.eks_us_west_2.oidc_provider_arn
  oidc_provider     = module.eks_us_west_2.oidc_provider

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Region      = "us-west-2"
  }

  depends_on = [module.eks_us_west_2]
}

# Provider configurations for Helm and Kubernetes
provider "helm" {
  alias = "us_east_1"
  kubernetes {
    host                   = module.eks_us_east_1.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_us_east_1.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_us_east_1.cluster_name, "--region", "us-east-1"]
    }
  }
}

provider "kubernetes" {
  alias = "us_east_1"
  host                   = module.eks_us_east_1.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_us_east_1.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_us_east_1.cluster_name, "--region", "us-east-1"]
  }
}

provider "helm" {
  alias = "us_west_2"
  kubernetes {
    host                   = module.eks_us_west_2.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_us_west_2.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_us_west_2.cluster_name, "--region", "us-west-2"]
    }
  }
}

provider "kubernetes" {
  alias = "us_west_2"
  host                   = module.eks_us_west_2.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_us_west_2.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_us_west_2.cluster_name, "--region", "us-west-2"]
  }
}