output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids_list" {
  description = "List of private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}
