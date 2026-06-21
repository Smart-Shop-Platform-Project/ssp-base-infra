output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "ecs_cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "alb_listener_arn" {
  value = module.alb.alb_listener_arn
}

# Cloud Map Output for Microservices
output "cloudmap_namespace_id" {
  description = "The ID of the Private DNS Namespace for Service Discovery"
  value       = aws_service_discovery_private_dns_namespace.ssp_local.id
}

# The following endpoints are also exported to SSM Parameter Store,
# but keeping them here is useful for referencing between modules
output "documentdb_endpoint" {
  value = module.documentdb.documentdb_endpoint
}

output "rds_endpoint" {
  value = module.rds.rds_endpoint
}

output "redis_endpoint" {
  value = module.elasticache.redis_endpoint
}

output "kafka_broker_private_ip" {
  value = aws_instance.kafka_broker.private_ip
}
