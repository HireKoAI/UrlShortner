#!/bin/bash
set -x
set -e
set -o pipefail

export PROFILE="hireko"
export ENVIRONMENT="prod"
export REGION=${4:-"us-west-1"}
export BASE_URL="short.hireko.ai"
export certificate_arn="arn:aws:acm:us-east-1:746669216128:certificate/83033caf-815b-483c-8bfb-af9a0b5f35b7"
export domain_name="hireko.ai"

# Source the utility functions
source infra/deploy_utils.sh

if ! aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
    echo "Error: Unable to access AWS with profile '$PROFILE'. Please check your credentials."
    exit 1
fi

# Run the deployment
deploy "$PROFILE" "$ENVIRONMENT" "$REGION" 