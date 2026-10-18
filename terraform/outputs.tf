output "db_public_ip"       { value = aws_instance.db.public_ip }
output "backend_ips"  { value = aws_instance.backend[*].public_ip}
output "frontend_ips" { value = aws_instance.frontend[*].public_ip }
output "db_private_ip"       { value = aws_instance.db.private_ip }
output "backend_alb_dns" {value = aws_lb.backend_alb.dns_name}
output "frontend_alb_dns" {value = aws_lb.frontend_alb.dns_name}