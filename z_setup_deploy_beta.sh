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
    mkdir -p $TEMP_TF_PATH
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
            $([ "${region}" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=${region}") ; then
            echo "Failed to create S3 bucket"
            exit 1
        fi

        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${backend_bucket}" \
            --profile "${profile}" \
            --versioning-configuration Status=Enabled

        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "${backend_bucket}" \
            --profile "${profile}" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'

        # Block public access
        aws s3api put-public-access-block \
            --bucket "${backend_bucket}" \
            --profile "${profile}" \
            --public-access-block-configuration '{
                "BlockPublicAcls": true,
                "IgnorePublicAcls": true,
                "BlockPublicPolicy": true,
                "RestrictPublicBuckets": true
            }'

        echo "Successfully created and configured S3 backend bucket"
    fi

    echo "${backend_bucket}"
}

# Create terraform vars file
create_tfvars() {
    local profile=$1
    local environment=$2
    local region=$3
    local tfvars_path=$4

    echo "project_name = \"${PROJECT_NAME}\"" > $tfvars_path
    echo "environment = \"${environment}\"" >> $tfvars_path
    echo "aws_profile = \"${profile}\"" >> $tfvars_path
    echo "aws_region = \"${region}\"" >> $tfvars_path
    echo "prefix = \"${environment}_${PROJECT_NAME}\"" >> $tfvars_path
    echo "env_muxoutbox_sql_db_endpoint = \"${MUXOUTBOX_SQL_DB_ENDPOINT}\"" >> $tfvars_path
    
    # # Add environment variables from shell environment
    # echo "livekit_url = \"${LIVEKIT_URL}\"" >> $tfvars_path
    # echo "livekit_api_key = \"${LIVEKIT_API_KEY}\"" >> $tfvars_path
    # echo "livekit_api_secret = \"${LIVEKIT_API_SECRET}\"" >> $tfvars_path
    # echo "groq_api_key = \"${GROQ_API_KEY}\"" >> $tfvars_path
    # echo "deepgram_api_key = \"${DEEPGRAM_API_KEY}\"" >> $tfvars_path
    
    # Add SMTP configuration if available
    if [ ! -z "${SMTP_HOST:-}" ]; then
        echo "smtp_host = \"${SMTP_HOST}\"" >> $tfvars_path
    fi
    
    if [ ! -z "${SMTP_PORT:-}" ]; then
        echo "smtp_port = \"${SMTP_PORT}\"" >> $tfvars_path
    fi
    
    if [ ! -z "${SMTP_USERNAME:-}" ]; then
        echo "smtp_username = \"${SMTP_USERNAME}\"" >> $tfvars_path
    fi
    
    if [ ! -z "${SMTP_PASSWORD:-}" ]; then
        echo "smtp_password = \"${SMTP_PASSWORD}\"" >> $tfvars_path
    fi
    
    if [ ! -z "${RECEIVING_EMAIL:-}" ]; then
        echo "receiving_email = \"${RECEIVING_EMAIL}\"" >> $tfvars_path
    fi
}

# Function to update CloudWatch log group retention
update_log_group_retention() {
    local profile=$1
    local environment=$2
    local lambda_name="${PROJECT_NAME}-api-${environment}"
    local log_group_name="/aws/lambda/${lambda_name}"

    echo "Checking CloudWatch log group: ${log_group_name}"

    # Check if log group exists
    if aws logs describe-log-groups \
        --log-group-name-prefix "${log_group_name}" \
        --profile "${profile}" \
        --query "logGroups[?logGroupName=='${log_group_name}'].logGroupName" \
        --output text &>/dev/null; then
        
        echo "Found existing log group. Updating retention period to 1 day..."
        
        # Update retention policy to 1 day
        aws logs put-retention-policy \
            --log-group-name "${log_group_name}" \
            --retention-in-days 1 \
            --profile "${profile}"
        
        echo "Successfully updated log group retention policy"
    else
        echo "Log group does not exist yet. Skipping retention update."
    fi
}

# Run terraform init, plan, and apply
run_terraform() {
    local profile=$1
    local environment=$2
    local region=$3
    local tfvars_path=$4
    local plan_path=$5
    local backend_bucket=$6

    cd infra/terraform

    echo "DEBUG: Initializing Terraform with backend config:"
    echo "  Region: ${region}"
    echo "  Key: ${PROJECT_NAME}/${environment}/terraform.tfstate"
    echo "  Profile: ${profile}"
    echo "  Bucket: ${backend_bucket}"

    # Initialize Terraform with S3 backend configuration
    echo "===== Starting Terraform Init ====="
    terraform init -reconfigure \
        -backend-config="bucket=${backend_bucket}" \
        -backend-config="region=${region}" \
        -backend-config="key=${PROJECT_NAME}/${environment}/terraform.tfstate" \
        -backend-config="profile=${profile}"

    # Import existing resources if they exist
    echo "===== Checking Existing Resources ====="
    check_and_import_resources "$profile" "$environment"

    echo "===== Starting Terraform Plan ====="
    if ! terraform plan \
        -var-file=$tfvars_path \
        -out=$plan_path \
        -lock=false \
        -input=false; then
        echo "Terraform plan failed. Please check the errors above."
        exit 1
    fi

    echo "===== Starting Terraform Apply ====="
    if ! terraform apply -lock=false $plan_path; then
        echo "Terraform apply failed. Please check the errors above."
        exit 1
    fi

    echo "===== Fetching Outputs ====="
    terraform refresh -var-file=$tfvars_path
    terraform output > "../terraform_outputs_${environment}.txt"


    cd ../..

    # Update log group retention after terraform deployment
    #update_log_group_retention "${profile}" "${environment}"
}

# Function to check and import existing resources
check_and_import_resources() {
    local profile=$1
    local environment=$2
    local lambda_name="${PROJECT_NAME}-api-${environment}"
    local role_name="${PROJECT_NAME}-role-${environment}"
    local api_name="${PROJECT_NAME}-api-${environment}"

    # Check if Lambda function exists
    if aws lambda get-function --function-name $lambda_name --profile $profile &>/dev/null; then
        echo "Found existing Lambda function: $lambda_name"
        terraform import aws_lambda_function.path_processor $lambda_name || true
    fi

    # Check if IAM role exists
    if aws iam get-role --role-name $role_name --profile $profile &>/dev/null; then
        echo "Found existing IAM role: $role_name"
        terraform import aws_iam_role.lambda_role $role_name || true
    fi

    # Check if API Gateway exists
    api_id=$(aws apigateway get-rest-apis --profile $profile --query "items[?name=='$api_name'].id" --output text)
    if [ ! -z "$api_id" ]; then
        echo "Found existing API Gateway: $api_name"
        terraform import aws_api_gateway_rest_api.api $api_id || true
    fi
}

# Create ZIP file for Lambda deployment
create_lambda_package() {
    local temp_dir=$(mktemp -d)
    local zip_file=$zip_file_name
    
    echo "Creating Lambda deployment package..."
    
    # Copy source files to temp directory, including subdirectories
    rsync -av --exclude='__pycache__' src/ "$temp_dir/"
    
    # Install Python dependencies
    echo "Installing Python dependencies..."
    python3.9 -m pip install -r src/requirements.txt --target "$temp_dir"
 
    # Explicitly install psycopg2-binary for Lambda compatibility
    echo "Installing psycopg2-binary..."
    
    python3.9 -m pip install --upgrade --only-binary=:all: psycopg2-binary -t "$temp_dir"
    export PYTHONPATH=$PYTHONPATH:"$temp_dir"

    # Create ZIP file
    cd "$temp_dir"
    zip -r "$zip_file" .
    cd - > /dev/null
    
    # Move ZIP to project root
    mv "$temp_dir/$zip_file" .
    
    # Cleanup
    rm -rf "$temp_dir"
    
    echo "Created Lambda package: $zip_file"
}


load_environment_variables() {

    profile=$1
    environment=$2

    export TENANT_UPPER=$(echo ${profile} | tr '[:lower:]' '[:upper:]')
    export STAGE_UPPER=$(echo ${environment} | tr '[:lower:]' '[:upper:]')

    local env_prefix="${TENANT_UPPER}_${STAGE_UPPER}"
    
    # local livekit_url_var="${env_prefix}_LIVEKIT_URL"
    # local livekit_key_var="${env_prefix}_LIVEKIT_API_KEY"
    # local livekit_secret_var="${env_prefix}_LIVEKIT_API_SECRET"
    # local groq_key_var="${env_prefix}_GROQ_API_KEY"
    # local deepgram_key_var="${env_prefix}_DEEPGRAM_API_KEY"
    
    # export LIVEKIT_URL=${!livekit_url_var:?Environment variable $livekit_url_var is required}
    # export LIVEKIT_API_KEY=${!livekit_key_var:?Environment variable $livekit_key_var is required}
    # export LIVEKIT_API_SECRET=${!livekit_secret_var:?Environment variable $livekit_secret_var is required}
    # export GROQ_API_KEY=${!groq_key_var:?Environment variable $groq_key_var is required}
    # export DEEPGRAM_API_KEY=${!deepgram_key_var:?Environment variable $deepgram_key_var is required}
}

# Main deployment function
deploy() {
    local profile=$1
    local environment=$2
    local region=$3

    load_environment_variables "$profile" "$environment"

    export zip_file_name="lambda_package.zip"
    
    # Create Lambda package first
    create_lambda_package
    
    init_deployment_vars "$profile" "$environment" "$region"
    
    # Create the backend bucket name
    local BACKEND_BUCKET="terraform-${environment}-${profile}-state"

    if [ "$environment" = "prod" ]; then
         BACKEND_BUCKET="${BACKEND_BUCKET}-collection"
     fi
    
    echo "DEBUG: Created backend bucket name: ${BACKEND_BUCKET}"
    
    # Setup S3 backend bucket
    setup_terraform_backend "$profile" "$region" "$BACKEND_BUCKET"
    
    echo "DEBUG: Backend bucket being passed to run_terraform: ${BACKEND_BUCKET}"
    
    TFVARS_FILE="${TEMP_TF_PATH}/terraform.tfvars"
    create_tfvars "$profile" "$environment" "$region" "$TFVARS_FILE"

    run_terraform "$profile" "$environment" "$region" "$TFVARS_FILE" "$LOCAL_TF_PLAN" "$BACKEND_BUCKET"
    
    # Cleanup the ZIP file after deployment
    rm -f $zip_file_name
} 