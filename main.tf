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

# --- Service Discovery ---
resource "aws_service_discovery_private_dns_namespace" "ssp" {
  name        = "ssp.local"
  description = "Private DNS namespace for the Smart Shop Platform"
  vpc         = module.vpc.vpc_id
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
  cluster_name    = "ssp-docdb"
  db_username     = "sspdocdb_owner"
}

module "rds" {
  source          = "git::https://github.com/DeathGod049/terraform-infra-child.git//modules/rds?ref=v0.1.0"
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  db_name         = "sspprd001"
  db_username     = "sspprd001_owner"
}

module "elasticache" {
  source          = "git::https://github.com/DeathGod049/terraform-infra-child.git//modules/elasticache?ref=v0.1.0"
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
}

# --- IAM Role for EC2 SSM Access ---
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ssp-ec2-ssm-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ssp-ec2-ssm-profile-${var.environment}"
  role = aws_iam_role.ec2_ssm_role.name
}

# --- Self-Managed Kafka (EC2) ---
resource "aws_security_group" "kafka" {
  name        = "ssp-kafka-sg-${var.environment}"
  description = "Allow traffic to Kafka"
  vpc_id      = module.vpc.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 9092
    to_port     = 9092
    cidr_blocks = ["10.0.0.0/16"] # Allow all traffic within VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "kafka_broker" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"
  subnet_id     = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.kafka.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = file("${path.module}/kafka_setup_kraft.sh")

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

# Added: SSM parameters for RDS connection strings
resource "aws_ssm_parameter" "auth_db_url" {
  name  = "/ssp/auth/database_url"
  type  = "SecureString"
  value = "postgresql://${module.rds.db_username}:${module.rds.password}@${module.rds.rds_endpoint}/${module.rds.db_name}"
}

resource "aws_ssm_parameter" "inventory_db_url" {
  name  = "/ssp/inventory/database_url"
  type  = "SecureString"
  value = "postgresql://${module.rds.db_username}:${module.rds.password}@${module.rds.rds_endpoint}/${module.rds.db_name}"
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
