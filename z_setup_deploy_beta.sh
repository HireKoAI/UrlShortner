#!/bin/bash
set -x
set -e
set -o pipefail

export PROFILE="hireko"
export ENVIRONMENT="beta"
export REGION=${4:-"us-west-2"} # Default to us-west-2 if not provided
export BASE_URL="shortbeta.hireko.ai"
export certificate_arn="arn:aws:acm:us-east-1:746669216128:certificate/acd10333-d739-4d0a-a64f-1cdad8733e0b"
export domain_name="hireko.ai"
# Source the utility functions
source infra/deploy_utils.sh

if ! aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
    echo "Error: Unable to access AWS with profile '$PROFILE'. Please check your credentials."
    exit 1
fi

# Run all unit tests in the test directory
echo "Running all unit tests..."
export PYTHONPATH=$PYTHONPATH:"./src":"./test"

# Run all unit tests in the test directory
echo "Running all unit tests..."
export PYTHONPATH=$PYTHONPATH:"./src":"./test"

#python3 -m unittest discover -s test -p "test_*.py" -v
source z_setup_run_functional_tests.sh

export TF_LOG=DEBUG
export TF_LOG_PATH=terraform-debug.log
# Run the deployment
deploy "$PROFILE" "$ENVIRONMENT" "$REGION" 