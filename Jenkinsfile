pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                // Initialize using the external backend.conf file
                sh 'terraform init -backend-config=backend.conf'
                sh 'terraform workspace select dev || terraform workspace new dev'
            }
        }

        stage('Terraform Plan') {
            steps {
                // Generate a plan and save it to 'tfplan' for a predictable apply
                // Note: Ensure all required variables are passed if not in a .tfvars file
                sh 'terraform plan -out=tfplan'
            }
        }

        stage('Approval') {
            steps {
                // Pause for manual review of the generated plan
                input message: 'Review the terraform plan. Proceed with apply?', ok: 'Apply'
            }
        }

        stage('Terraform Apply') {
            steps {
                // Apply the exact plan saved in the previous stage
                sh 'terraform apply -auto-approve tfplan'
            }
        }
    }
}
