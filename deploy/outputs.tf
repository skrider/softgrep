output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "bastion_public_ip" {
  description = "Bastion public ip"
  value       = aws_eip.bastion.public_ip
}

output "bastion_private_key" {
  description = "bastion private key"
  value       = tls_private_key.bastion.private_key_pem
  sensitive   = true
}

output "cluster_private_key" {
  description = "cluster private key"
  value       = tls_private_key.cluster.private_key_pem
  sensitive   = true
}

output "server_ecr_url" {
  description = "Server Registry Name"
  value       = aws_ecr_repository.server.repository_url
}

output "ray_service" {
  description = ""
  value = "${helm_release.ray_cluster.name}-kuberay-head-svc.${kubernetes_namespace.ray.metadata[0].name}.svc.cluster.local"
}
