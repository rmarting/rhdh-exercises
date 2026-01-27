#!/bin/bash

# Post-configure GitLab CI/CD variables for TechDocs
# This script configures the GitLab CI/CD variables needed for TechDocs pipelines
# and patches the RHDH secrets with bucket information.

# Running from same folder
cd $(dirname $0)

# Set default values
ssl_certs_self_signed="n"

# Iterate over command-line arguments
for arg in "$@"; do
    case $arg in
        --ssl_certs_self_signed=*)
            ssl_certs_self_signed="${arg#*=}"
            ;;
        *)
            # Other arguments are ignored
            ;;
    esac
done

# Check if insecure flag is set to 'y'
if [ "$ssl_certs_self_signed" = "y" ]; then
    echo "SSL Certificates self signed enabled."
    CURL_DISABLE_SSL_VERIFICATION="-k"
fi

# Check required CLI's
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Aborting."; exit 1; }
command -v oc >/dev/null 2>&1 || { echo >&2 "OpenShift CLI is required but not installed. Aborting."; exit 1; }

# GitLab token must be 20 characters
DEFAULT_GITLAB_TOKEN="KbfdXFhoX407c0v5ZP2Y"

GITLAB_TOKEN=${GITLAB_TOKEN:=$DEFAULT_GITLAB_TOKEN}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:=gitlab-system}
RHDH_NAMESPACE=${RHDH_NAMESPACE:=rhdh-gitlab}

GITLAB_URL=https://$(oc get ingress -n $GITLAB_NAMESPACE -l app=webservice -o jsonpath='{ .items[*].spec.rules[*].host }')

echo "GitLab URL: $GITLAB_URL"
echo ""

# ============================================
# Step 1: Retrieve values from OpenShift
# ============================================
echo "--- Retrieving TechDocs bucket configuration ---"

# Check if the bucket claim resources exist
if ! oc get secret rhdh-techdocs-bucket-claim -n $RHDH_NAMESPACE &>/dev/null; then
    echo "ERROR: Secret 'rhdh-techdocs-bucket-claim' not found in namespace $RHDH_NAMESPACE."
    echo "Please ensure the ObjectBucketClaim has been created and is bound."
    exit 1
fi

if ! oc get configmap rhdh-techdocs-bucket-claim -n $RHDH_NAMESPACE &>/dev/null; then
    echo "ERROR: ConfigMap 'rhdh-techdocs-bucket-claim' not found in namespace $RHDH_NAMESPACE."
    echo "Please ensure the ObjectBucketClaim has been created and is bound."
    exit 1
fi

# Get AWS_ENDPOINT from S3 route
AWS_ENDPOINT=$(oc get route s3 -n openshift-storage -o jsonpath='https://{.spec.host}' 2>/dev/null)
if [ -z "$AWS_ENDPOINT" ]; then
    echo "ERROR: Could not get S3 route from openshift-storage namespace."
    echo "Please ensure OpenShift Data Foundation is properly configured."
    exit 1
fi
echo "AWS_ENDPOINT: $AWS_ENDPOINT"

# Get AWS_ACCESS_KEY_ID from bucket claim secret
AWS_ACCESS_KEY_ID=$(oc get secret rhdh-techdocs-bucket-claim -n $RHDH_NAMESPACE -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "ERROR: Could not retrieve AWS_ACCESS_KEY_ID from secret."
    exit 1
fi
echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:5}... (truncated)"

# Get AWS_SECRET_ACCESS_KEY from bucket claim secret
AWS_SECRET_ACCESS_KEY=$(oc get secret rhdh-techdocs-bucket-claim -n $RHDH_NAMESPACE -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERROR: Could not retrieve AWS_SECRET_ACCESS_KEY from secret."
    exit 1
fi
echo "AWS_SECRET_ACCESS_KEY: ****** (hidden)"

# Get BUCKET_NAME from bucket claim configmap
TECHDOCS_S3_BUCKET_NAME=$(oc get configmap rhdh-techdocs-bucket-claim -n $RHDH_NAMESPACE -o jsonpath='{.data.BUCKET_NAME}')
if [ -z "$TECHDOCS_S3_BUCKET_NAME" ]; then
    echo "ERROR: Could not retrieve BUCKET_NAME from configmap."
    exit 1
fi
echo "TECHDOCS_S3_BUCKET_NAME: $TECHDOCS_S3_BUCKET_NAME"

# Set AWS_REGION
AWS_REGION="us-east-2"
echo "AWS_REGION: $AWS_REGION"

echo ""

# ============================================
# Step 2: Configure GitLab CI/CD Variables
# ============================================
echo "--- Configuring GitLab CI/CD Variables ---"

# Function to create or update a GitLab CI/CD variable
set_gitlab_variable() {
    local key=$1
    local value=$2
    local protected=${3:-false}
    local masked=${4:-false}
    
    # Check if variable already exists
    EXISTING=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "${GITLAB_URL}/api/v4/admin/ci/variables/${key}" 2>/dev/null | jq -r '.key // empty')
    
    if [ -n "$EXISTING" ]; then
        echo "Updating variable: $key"
        curl $CURL_DISABLE_SSL_VERIFICATION -s --request PUT \
            --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --form "value=${value}" \
            --form "protected=${protected}" \
            --form "masked=${masked}" \
            --form "raw=true" \
            "${GITLAB_URL}/api/v4/admin/ci/variables/${key}" &>/dev/null
    else
        echo "Creating variable: $key"
        curl $CURL_DISABLE_SSL_VERIFICATION -s --request POST \
            --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --form "key=${key}" \
            --form "value=${value}" \
            --form "protected=${protected}" \
            --form "masked=${masked}" \
            --form "raw=true" \
            "${GITLAB_URL}/api/v4/admin/ci/variables" &>/dev/null
    fi
}

# Set the CI/CD variables
set_gitlab_variable "AWS_ENDPOINT" "$AWS_ENDPOINT" "false" "false"
set_gitlab_variable "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID" "false" "true"
set_gitlab_variable "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY" "false" "true"
set_gitlab_variable "TECHDOCS_S3_BUCKET_NAME" "$TECHDOCS_S3_BUCKET_NAME" "false" "false"
set_gitlab_variable "AWS_REGION" "$AWS_REGION" "false" "false"

echo ""

# Verify variables were created
echo "Verifying GitLab CI/CD variables..."
VARS=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "${GITLAB_URL}/api/v4/admin/ci/variables" | jq -r '.[].key' 2>/dev/null)

EXPECTED_VARS="AWS_ENDPOINT AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TECHDOCS_S3_BUCKET_NAME AWS_REGION"
ALL_FOUND=true
for var in $EXPECTED_VARS; do
    if echo "$VARS" | grep -q "^${var}$"; then
        echo "  ✓ $var"
    else
        echo "  ✗ $var (not found)"
        ALL_FOUND=false
    fi
done

if [ "$ALL_FOUND" = false ]; then
    echo ""
    echo "WARNING: Some variables were not created. Please check manually in GitLab Admin Area."
fi

echo ""

# ============================================
# Step 3: Patch RHDH secrets
# ============================================
echo "--- Patching RHDH secrets ---"

# Encode values for patching
AWS_REGION_B64=$(echo -n "$AWS_REGION" | base64 -w0 2>/dev/null || echo -n "$AWS_REGION" | base64)
BUCKET_URL_B64=$(echo -n "$AWS_ENDPOINT" | base64 -w0 2>/dev/null || echo -n "$AWS_ENDPOINT" | base64)

echo "Patching rhdh-secrets with AWS_REGION..."
oc patch secret rhdh-secrets -n $RHDH_NAMESPACE -p '{"data":{"AWS_REGION":"'"${AWS_REGION_B64}"'"}}'

echo "Patching rhdh-secrets with BUCKET_URL..."
oc patch secret rhdh-secrets -n $RHDH_NAMESPACE -p '{"data":{"BUCKET_URL":"'"${BUCKET_URL_B64}"'"}}'

echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=============================================="
echo "  TechDocs CI/CD Configuration Complete!"
echo "=============================================="
echo ""
echo "GitLab CI/CD Variables configured:"
echo "  - AWS_ENDPOINT: $AWS_ENDPOINT"
echo "  - AWS_ACCESS_KEY_ID: (masked)"
echo "  - AWS_SECRET_ACCESS_KEY: (masked)"
echo "  - TECHDOCS_S3_BUCKET_NAME: $TECHDOCS_S3_BUCKET_NAME"
echo "  - AWS_REGION: $AWS_REGION"
echo ""
echo "RHDH secrets patched with:"
echo "  - AWS_REGION"
echo "  - BUCKET_URL"
echo ""
echo "You can verify the GitLab variables at:"
echo "  ${GITLAB_URL}/admin/application_settings/ci_cd (Variables section)"
echo ""
