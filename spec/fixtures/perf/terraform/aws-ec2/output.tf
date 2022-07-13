output "kong-ip" {
  value = aws_instance.kong.public_ip
}

output "kong-internal-ip" {
  value = aws_instance.kong.private_ip
}

output "db-ip" {
  value = aws_instance.db.public_ip
}

output "db-internal-ip" {
  value = aws_instance.db.private_ip
}

output "worker-ip" {
  value = aws_instance.worker.public_ip
}

output "worker-internal-ip" {
  value = aws_instance.worker.private_ip
}
