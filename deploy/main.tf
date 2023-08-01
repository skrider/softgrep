provider "aws" {
  region = var.region
}

provider "tls" {}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

data "aws_availability_zones" "available" {}

locals {
  name            = "softgrep"
  cluster_name    = "${local.name}-${var.env}-${random_string.suffix.result}"
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_cidr        = "10.0.0.0/16"
  cluster_version = "1.27"
  tags = {
    GithubRepo = "softgrep"
    GithubOrg  = "skrider"
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "${local.name}-${var.env}-vpc"

  cidr = local.vpc_cidr
  azs  = local.azs
  # private subnets aren't private, there is a NAT table rule that allows all external
  # traffic.
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 3)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 6)]

  enable_nat_gateway = true
  single_nat_gateway = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
}

################################################################################
# ECR
################################################################################

resource "aws_ecr_repository" "server" {
  name                 = "softgrep-${lower(random_string.suffix.result)}/server"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.4"

  cluster_name                   = local.cluster_name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # cluster_security_group_additional_rules = {
  #   ingress_ssh = {
  #     description                = "SSH from vpc to cluster"
  #     protocol                   = "tcp"
  #     from_port                  = 0
  #     to_port                    = 22
  #     type                       = "ingress"
  #     cidr_blocks = [local.vpc_cidr]
  #   }
  # }

  eks_managed_node_groups = {
    # Default node group - as provided by AWS EKS
    worker = {
      # By default, the module creates a launch template to ensure tags are propagated to instances, etc.,
      # so we need to disable it to use the default template provided by the AWS EKS managed node group service
      use_custom_launch_template = false

      min_size     = 3
      max_size     = 10
      desired_size = 3

      ami_type = "AL2_x86_64"
      platform = "linux"

      disk_size = 64

      instance_types = ["m5.xlarge"]

      # Remote access cannot be specified with a launch template
      remote_access = {
        ec2_ssh_key               = aws_key_pair.cluster.key_name
        source_security_group_ids = [aws_security_group.bastion.id]
      }
    }

    gpu_worker = {
      # By default, the module creates a launch template to ensure tags are propagated to instances, etc.,
      # so we need to disable it to use the default template provided by the AWS EKS managed node group service
      use_custom_launch_template = false

      min_size     = 1
      max_size     = 2
      desired_size = 1

      ami_type = "AL2_x86_64_GPU"
      platform = "linux"

      disk_size = 256

      instance_types = ["g5.xlarge"]

      # Remote access cannot be specified with a launch template
      remote_access = {
        ec2_ssh_key               = aws_key_pair.cluster.key_name
        source_security_group_ids = [aws_security_group.bastion.id]
      }
    }
  }
}

resource "tls_private_key" "cluster" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "cluster" {
  key_name   = "${local.cluster_name}-key-pair"
  public_key = tls_private_key.cluster.public_key_openssh
}

resource "aws_security_group" "cluster_ssh" {
  name_prefix = "${local.cluster_name}-remote-access"
  description = "Allow remote SSH access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 0
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-remote" })
}

################################################################################
# Bastion
################################################################################

resource "aws_eip" "bastion" {}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "${local.cluster_name}-dev-key-pair"
  public_key = tls_private_key.bastion.public_key_openssh
}

resource "aws_security_group" "bastion" {
  name        = "bastion"
  description = "bastion security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from laptop"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # replace this with your IP/CIDR
  }

  egress {
    description = "SSH to cluster"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr] # replace this with your IP/CIDR
  }

  tags = {
    Name = "dev-ssh"
  }
}

data "aws_ami" "latest_amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  owners = ["amazon"]
}

resource "aws_instance" "bastion" {
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.bastion.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  subnet_id              = module.vpc.public_subnets[0]
  ami                    = data.aws_ami.latest_amazon_linux.id

  tags = {
    Name = "${local.cluster_name}-dev"
  }
}

################################################################################
# Helm
################################################################################

resource "kubernetes_namespace" "gpu_operator" {
  metadata {
    name = "gpu-operator"
  }
}

resource "helm_release" "gpu_operator" {
  name       = "gpu-operator"
  atomic     = true
  chart      = "gpu-operator"
  version    = "23.3.2"
  repository = "https://helm.ngc.nvidia.com/nvidia"
  namespace  = kubernetes_namespace.gpu_operator.metadata[0].name
  wait       = true

  values = [
    <<EOF
    cdi:
        enabled: true
        default: true
    driver:
        enabled: false
    toolkit:
        enabled: true
    EOF
  ]
}

resource "null_resource" "wait_for_gpu" {
  provisioner "local-exec" {
    command = <<EOF
/bin/env sh -c "$(cat << EOS
kubectl config use-context ${module.eks.cluster_arn}
until [[ $(kubectl get nodes -l nvidia.com/gpu.present=true | wc -l) > 0 ]]; do 
    echo 'Waiting for node label...' 
    sleep 5
done
EOS
)"
EOF
  }

  depends_on = [helm_release.gpu_operator]
}

resource "kubernetes_namespace" "ray" {
  metadata {
    name = "ray"
  }
}

resource "helm_release" "ray_operator" {
  name       = "ray-operator"
  atomic     = true
  chart      = "kuberay-operator"
  namespace  = kubernetes_namespace.ray.metadata[0].name
  repository = "https://ray-project.github.io/kuberay-helm"
  version    = "0.6.0-rc.1"

  depends_on = [null_resource.wait_for_gpu]
}

resource "helm_release" "ray_cluster" {
  name       = "ray-cluster"
  atomic     = true
  namespace  = kubernetes_namespace.ray.metadata[0].name
  chart      = "ray-cluster"
  repository = "https://ray-project.github.io/kuberay-helm"
  version    = "0.6.0-rc.1"

  values = [
    file("${path.module}/values/ray-cluster.yaml")
  ]

  depends_on = [helm_release.ray_operator, null_resource.wait_for_gpu]
}

