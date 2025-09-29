#!/bin/bash

# Initialize common variables
init_deployment_vars() {
    local profile=$1
    local environment=$2
    local region=$3

    # Get project name from directory name
    PROJECT_NAME=$(basename $(pwd))

    echo "Deploying project: ${PROJECT_NAME}"
    echo "Environment: ${environment}"
    echo "AWS Profile: ${profile}"
    echo "AWS Region: ${region}"

    # Create temporary directory for Terraform files
    TEMP_TF_PATH="$(pwd)/infra/terraform/.terraform"
    LOCAL_TF_PLAN="${TEMP_TF_PATH}/${PROJECT_NAME}_${environment}.tfplan"
    mkdir -p "$TEMP_TF_PATH"
}

# Create and configure S3 backend bucket
setup_terraform_backend() {
    local profile=$1
    local region=$2
    local backend_bucket=$3
    
    echo "DEBUG: Attempting to access bucket: ${backend_bucket}"
    echo "DEBUG: Using AWS Profile: ${profile}"
    echo "DEBUG: Using Region: ${region}"
    
    # Check if bucket exists with more verbose output
    if ! aws s3 ls "s3://${backend_bucket}" --profile "${profile}" --region "${region}" 2>/dev/null; then
         echo "Failed to access bucket ${backend_bucket}"
         bucket_check=1
     else
         bucket_check=0
     fi
    echo "DEBUG: Bucket check exit code: ${bucket_check}"

    if [ $bucket_check -eq 0 ]; then
        echo "Using existing S3 backend bucket: ${backend_bucket}"
    else
        echo "Creating new S3 backend bucket: ${backend_bucket}"
        # Create the bucket
        if ! aws s3api create-bucket \
            --bucket "${backend_bucket}" \
            --profile "${profile}" \
            --region "${region}" \
            --create-bucket-configuration LocationConstraint="${region}"; then
            echo "Failed to create S3 bucket: ${backend_bucket}"
            exit 1
        fi

        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${backend_bucket}" \
            --versioning-configuration Status=Enabled \
            --profile "${profile}" \
            --region "${region}"

        # Enable server-side encryption
        aws s3api put-bucket-encryption \
            --bucket "${backend_bucket}" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }' \
            --profile "${profile}" \
            --region "${region}"

        echo "S3 backend bucket created and configured: ${backend_bucket}"
    fi
}

# Package Lambda functions
package_lambda() {
    echo "Packaging Lambda functions..."
    
    # Remove existing package
    rm -f lambda_package.zip
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    
    # Copy source code
    cp -r src/* "${TEMP_DIR}/"
    
    # Install dependencies
    pip3 install -r src/requirements.txt -t "${TEMP_DIR}/" --upgrade
    
    # Create zip package
    cd "${TEMP_DIR}"
    zip -r "${OLDPWD}/lambda_package.zip" . -x "*.pyc" "*__pycache__*"
    cd "${OLDPWD}"
    
    # Clean up
    rm -rf "${TEMP_DIR}"
    
    echo "Lambda package created: lambda_package.zip"
}

# Initialize Terraform
init_terraform() {
    local profile=$1
    local environment=$2
    local region=$3
    local backend_bucket=$4

    cd infra/terraform

    # Initialize Terraform with backend configuration
    terraform init \
        -backend-config="bucket=${backend_bucket}" \
        -backend-config="key=${PROJECT_NAME}/${environment}/terraform.tfstate" \
        -backend-config="region=${region}" \
        -backend-config="profile=${profile}" \
        -reconfigure

    cd ../..
}

# Plan Terraform deployment
plan_terraform() {
    local profile=$1
    local environment=$2
    local region=$3

    cd infra/terraform

    # Create Terraform plan
    terraform plan \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${environment}" \
        -var="aws_profile=${profile}" \
        -var="aws_region=${region}" \
        -var="prefix=${PROJECT_NAME}-${environment}" \
        -var="base_url=${BASE_URL:-}" \
        -var="certificate_arn=${certificate_arn:-}" \
        -var="domain_name=${domain_name:-}" \
        -out="${LOCAL_TF_PLAN}"

    cd ../..
}

# Apply Terraform deployment
apply_terraform() {
    local profile=$1
    local environment=$2

    cd infra/terraform

    # Apply Terraform plan
    terraform apply "${LOCAL_TF_PLAN}"

    # Generate outputs
    terraform output > "../../terraform_outputs_${environment}.txt"

    cd ../..
}

# Main deployment function
deploy() {
    local profile=$1
    local environment=$2
    local region=$3

    # Initialize variables
    init_deployment_vars "$profile" "$environment" "$region"

    # Set backend bucket name
    BACKEND_BUCKET="hireko-terraform-state-${region}"

    echo "Starting deployment for ${PROJECT_NAME} in ${environment} environment"

    # Setup S3 backend
    setup_terraform_backend "$profile" "$region" "$BACKEND_BUCKET"

    # Package Lambda functions
    package_lambda

    # Initialize Terraform
    init_terraform "$profile" "$environment" "$region" "$BACKEND_BUCKET"

    # Plan deployment
    plan_terraform "$profile" "$environment" "$region"

    # Apply deployment
    apply_terraform "$profile" "$environment"

    echo "Deployment completed successfully!"
    echo "Terraform outputs saved to: terraform_outputs_${environment}.txt"
}

# Destroy infrastructure
destroy() {
    local profile=$1
    local environment=$2
    local region=$3

    # Initialize variables
    init_deployment_vars "$profile" "$environment" "$region"

    # Set backend bucket name
    BACKEND_BUCKET="hireko-terraform-state-${region}"

    cd infra/terraform

    # Initialize Terraform with backend configuration
    terraform init \
        -backend-config="bucket=${BACKEND_BUCKET}" \
        -backend-config="key=${PROJECT_NAME}/${environment}/terraform.tfstate" \
        -backend-config="region=${region}" \
        -backend-config="profile=${profile}" \
        -reconfigure

    # Destroy infrastructure
    terraform destroy \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${environment}" \
        -var="aws_profile=${profile}" \
        -var="aws_region=${region}" \
        -var="prefix=${PROJECT_NAME}-${environment}" \
        -var="base_url=${BASE_URL:-}" \
        -var="certificate_arn=${certificate_arn:-}" \
        -var="domain_name=${domain_name:-}" \
        -auto-approve

    cd ../..

    echo "Infrastructure destroyed successfully!"
} 