output "kong-ip" {
  value = aws_instance.kong.public_ip
}

output "kong-internal-ip" {
  value = aws_instance.kong.private_ip
}

output "db-ip" {
  value = var.seperate_db_node ? aws_instance.db.0.public_ip: ""
}

output "db-internal-ip" {
  value = var.seperate_db_node ? aws_instance.db.0.private_ip: ""
}

output "worker-ip" {
  value = aws_instance.worker.public_ip
}

output "worker-internal-ip" {
  value = aws_instance.worker.private_ip
}
