#!/bin/bash

# Log all output to a file for debugging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting Kafka KRaft mode installation..."

# 1. Install Dependencies
sudo apt-get update -y
sudo apt-get install -y default-jre wget

# 2. Download and Extract Kafka
KAFKA_VERSION="3.6.1"
SCALA_VERSION="2.13"
wget https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
tar -xzf kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
mv kafka_${SCALA_VERSION}-${KAFKA_VERSION} /opt/kafka
cd /opt/kafka

# 3. Configure Kafka in KRaft mode
# Generate a unique Cluster ID
CLUSTER_ID=$(bin/kafka-storage.sh random-uuid)

# Get the private IP address of the EC2 instance
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Configure the KRaft properties file (config/kraft/server.properties)
# This replaces the old zookeeper.properties and server.properties
sed -i "s/process.roles=broker,controller/process.roles=broker,controller/g" config/kraft/server.properties
sed -i "s/controller.quorum.voters=1@localhost:9093/controller.quorum.voters=1@$PRIVATE_IP:9093/g" config/kraft/server.properties
sed -i "s/listeners=PLAINTEXT:\/\/localhost:9092,CONTROLLER:\/\/localhost:9093/listeners=PLAINTEXT:\/\/:9092,CONTROLLER:\/\/:9093/g" config/kraft/server.properties
sed -i "s/advertised.listeners=PLAINTEXT:\/\/localhost:9092/advertised.listeners=PLAINTEXT:\/\/$PRIVATE_IP:9092/g" config/kraft/server.properties

# Format the log directory with the new Cluster ID
bin/kafka-storage.sh format -t $CLUSTER_ID -c config/kraft/server.properties

# 4. Start the Kafka Server in KRaft mode
echo "Starting Kafka in KRaft mode..."
nohup bin/kafka-server-start.sh config/kraft/server.properties > /var/log/kafka.log 2>&1 &

echo "Kafka KRaft installation and startup complete."
