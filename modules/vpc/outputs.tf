output "vpc_id" {
  value = aws_vpc.main.id
}

output "cluster_name" {
  value       = var.cluster_name
}

output "public_subnet_ids_list" {
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids_list" {
  value       = [for s in aws_subnet.private : s.id]
}
