output "cluster_id" {
  value = aws_eks_cluster.blog_site.id
}

output "node_group_id" {
  value = aws_eks_node_group.blog_site.id
}

output "vpc_id" {
  value = aws_vpc.blog_site_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.blog_site_subnet[*].id
}

output "aws_load_balancer_controller_role_arn" {
  value = aws_iam_role.aws_load_balancer_controller.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.blog_site_oidc.arn
}
