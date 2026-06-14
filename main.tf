terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
  backend "s3" {
    bucket = "ssp-terraform-state-bucket"
    key    = "infrastructure/base/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" { region = var.aws_region }

# --- VPC & Networking ---
module "vpc" {
  source = "git::https://github.com/DeathGod049/terraform-infra-child.git//modules/vpc?ref=v0.1.0"

  vpc_name       = "ssp-vpc-${var.environment}"
  environment    = var.environment
  vpc_cidr       = "10.0.0.0/16"
  public_subnets = ["10.0.1.0/24", "10.0.3.0/24"]
  private_subnets= ["10.0.2.0/24", "10.0.4.0/24"]
  azs            = ["${var.aws_region}a", "${var.aws_region}b"]
}

# --- Shared ALB ---
module "alb" {
  source         = "git::https://github.com/DeathGod049/terraform-infra-child.git//modules/alb?ref=v0.1.0"
  vpc_id         = module.vpc.vpc_id
  public_subnets = module.vpc.public_subnets
  environment    = var.environment
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "ssp-cluster-${var.environment}"
}

# --- Databases (DocumentDB, RDS, ElastiCache) ---
module "documentdb" {
  source          = "git::https://github.com/DeathGod049/terraform-infra-child.git//modules/documentdb?ref=v0.1.0"
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
}

module "rds" {
  source          = "git::https://github.com/DeathGod049/terraform-infra-child.git//modules/rds?ref=v0.1.0"
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
}

module "elasticache" {
  source          = "git::https://github.com/DeathGod049/terraform-infra-child.git//modules/elasticache?ref=v0.1.0"
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
}

# --- Self-Managed Kafka (EC2) Placeholder ---
resource "aws_instance" "kafka_broker" {
  ami           = "ami-0c7217cdde317cfec" # Example Ubuntu AMI, change as needed
  instance_type = "t3.small"
  subnet_id     = module.vpc.private_subnets[0]

  tags = {
    Name = "ssp-kafka-broker-${var.environment}"
  }
}

# --- Output to SSM Parameter Store ---

resource "aws_ssm_parameter" "mongo_uri" {
  name  = "/ssp/product/mongo_uri"
  type  = "SecureString"
  value = module.documentdb.documentdb_connection_string
}

resource "aws_ssm_parameter" "redis_host" {
  name  = "/ssp/cart/redis_host"
  type  = "String"
  value = module.elasticache.redis_endpoint
}

resource "aws_ssm_parameter" "kafka_broker_url" {
  name  = "/ssp/shared/kafka_broker_url"
  type  = "String"
  value = "${aws_instance.kafka_broker.private_ip}:9092"
}

# These are placeholders; you'll need to create the actual services/endpoints
resource "aws_ssm_parameter" "sagemaker_endpoint" {
  name  = "/ssp/ai/recommender_endpoint_name"
  type  = "String"
  value = "placeholder-sagemaker-endpoint"
}

resource "aws_ssm_parameter" "fraud_model_id" {
  name  = "/ssp/ai/fraud_model_id"
  type  = "String"
  value = "anthropic.claude-v2"
}

resource "aws_ssm_parameter" "opensearch_host" {
  name  = "/ssp/search/opensearch_host"
  type  = "String"
  value = "placeholder-opensearch-domain.us-east-1.es.amazonaws.com"
}
