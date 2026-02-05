#!/usr/bin/env bash
set -euo pipefail

# Post-configure GitLab CI/CD variables for TechDocs
# This script configures the GitLab CI/CD variables needed for TechDocs pipelines
# and patches the RHDH secrets with bucket information.

# Source common functions
source "$(dirname "$0")/common.sh"

# ============================================
# Usage
# ============================================
usage() {
    cat <<EOF
Usage: $0 [options]

Configures GitLab CI/CD variables for TechDocs pipelines.

Options:
  -k, --insecure-ssl    Bypass SSL verification for self-signed certs
  -h, --help            Show this help message

Examples:
  $0                    # Configure with default SSL verification
  $0 -k                 # Bypass SSL verification (self-signed certs)
EOF
    exit "${1:-0}"
}

# ============================================
# Parse Arguments
# ============================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--insecure-ssl)
            INSECURE_SSL=true
            CURL_DISABLE_SSL_VERIFICATION="-k"
            log_info "SSL verification bypass enabled (self-signed certs)"
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage 1
            ;;
    esac
done

# Check required CLI's
check_basic_clis

# Get GitLab token (will exit if not available)
GITLAB_TOKEN=$(get_gitlab_token)

# Get GitLab URL
GITLAB_URL=$(get_gitlab_url)

log_info "GitLab URL: $GITLAB_URL"
echo ""

# ============================================
# Step 1: Retrieve values from OpenShift
# ============================================
print_section "Retrieving TechDocs bucket configuration"

# Check if the bucket claim resources exist
if ! resource_exists "secret" "rhdh-techdocs-bucket-claim" "$RHDH_NAMESPACE"; then
    log_error "Secret 'rhdh-techdocs-bucket-claim' not found in namespace $RHDH_NAMESPACE."
    log_error "Please ensure the ObjectBucketClaim has been created and is bound."
    exit 1
fi

if ! resource_exists "configmap" "rhdh-techdocs-bucket-claim" "$RHDH_NAMESPACE"; then
    log_error "ConfigMap 'rhdh-techdocs-bucket-claim' not found in namespace $RHDH_NAMESPACE."
    log_error "Please ensure the ObjectBucketClaim has been created and is bound."
    exit 1
fi

# Get all bucket claim values in a single API call
BUCKET_SECRET_JSON=$(oc get secret rhdh-techdocs-bucket-claim -n "$RHDH_NAMESPACE" -o json)
BUCKET_CM_JSON=$(oc get configmap rhdh-techdocs-bucket-claim -n "$RHDH_NAMESPACE" -o json)

# Get AWS_ENDPOINT from S3 route
AWS_ENDPOINT=$(oc get route s3 -n openshift-storage -o jsonpath='https://{.spec.host}' 2>/dev/null)
if [ -z "$AWS_ENDPOINT" ]; then
    log_error "Could not get S3 route from openshift-storage namespace."
    log_error "Please ensure OpenShift Data Foundation is properly configured."
    exit 1
fi
log_info "AWS_ENDPOINT: $AWS_ENDPOINT"

# Get AWS_ACCESS_KEY_ID from bucket claim secret
AWS_ACCESS_KEY_ID=$(echo "$BUCKET_SECRET_JSON" | jq -r '.data.AWS_ACCESS_KEY_ID' | base64_decode)
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    log_error "Could not retrieve AWS_ACCESS_KEY_ID from secret."
    exit 1
fi
log_info "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:5}... (truncated)"

# Get AWS_SECRET_ACCESS_KEY from bucket claim secret
AWS_SECRET_ACCESS_KEY=$(echo "$BUCKET_SECRET_JSON" | jq -r '.data.AWS_SECRET_ACCESS_KEY' | base64_decode)
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    log_error "Could not retrieve AWS_SECRET_ACCESS_KEY from secret."
    exit 1
fi
log_info "AWS_SECRET_ACCESS_KEY: ****** (hidden)"

# Get BUCKET_NAME from bucket claim configmap
TECHDOCS_S3_BUCKET_NAME=$(echo "$BUCKET_CM_JSON" | jq -r '.data.BUCKET_NAME')
if [ -z "$TECHDOCS_S3_BUCKET_NAME" ]; then
    log_error "Could not retrieve BUCKET_NAME from configmap."
    exit 1
fi
log_info "TECHDOCS_S3_BUCKET_NAME: $TECHDOCS_S3_BUCKET_NAME"

# AWS_REGION from config.env
log_info "AWS_REGION: $AWS_REGION"

echo ""

# ============================================
# Step 2: Configure GitLab CI/CD Variables
# ============================================
print_section "Configuring GitLab CI/CD Variables"

# Set the CI/CD variables
set_gitlab_variable "AWS_ENDPOINT" "$AWS_ENDPOINT" "$GITLAB_TOKEN" "$GITLAB_URL" "false" "false"
set_gitlab_variable "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID" "$GITLAB_TOKEN" "$GITLAB_URL" "false" "true"
set_gitlab_variable "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY" "$GITLAB_TOKEN" "$GITLAB_URL" "false" "true"
set_gitlab_variable "TECHDOCS_S3_BUCKET_NAME" "$TECHDOCS_S3_BUCKET_NAME" "$GITLAB_TOKEN" "$GITLAB_URL" "false" "false"
set_gitlab_variable "AWS_REGION" "$AWS_REGION" "$GITLAB_TOKEN" "$GITLAB_URL" "false" "false"

echo ""

# Verify variables were created
log_info "Verifying GitLab CI/CD variables..."
VARS=$(gitlab_api_get "/api/v4/admin/ci/variables" "$GITLAB_TOKEN" "$GITLAB_URL" | jq -r '.[].key' 2>/dev/null)

EXPECTED_VARS="AWS_ENDPOINT AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TECHDOCS_S3_BUCKET_NAME AWS_REGION"
ALL_FOUND=true
for var in $EXPECTED_VARS; do
    if echo "$VARS" | grep -q "^${var}$"; then
        echo "  [OK] $var"
    else
        echo "  [MISSING] $var"
        ALL_FOUND=false
    fi
done

if [ "$ALL_FOUND" = false ]; then
    echo ""
    log_warn "Some variables were not created. Please check manually in GitLab Admin Area."
fi

echo ""

# ============================================
# Step 3: Patch RHDH secrets
# ============================================
print_section "Patching RHDH secrets"

log_info "Patching rhdh-secrets with AWS_REGION..."
patch_secret "rhdh-secrets" "AWS_REGION" "$AWS_REGION" "$RHDH_NAMESPACE"

log_info "Patching rhdh-secrets with BUCKET_URL..."
patch_secret "rhdh-secrets" "BUCKET_URL" "$AWS_ENDPOINT" "$RHDH_NAMESPACE"

print_banner "TechDocs CI/CD Configuration Complete!"

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
