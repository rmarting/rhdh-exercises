#!/bin/bash

# Post-configure GitLab for RHDH authentication
# This script creates a GitLab OAuth application, a Personal Access Token (PAT),
# and creates the gitlab-secrets Kubernetes secret.

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
BASEDOMAIN=$(oc get ingress -n $GITLAB_NAMESPACE -l app=webservice -o jsonpath='{ .items[*].spec.rules[*].host }' | sed 's/^gitlab\.//')

# RHDH redirect URI for OAuth
REDIRECT_URI="https://backstage-developer-hub-${RHDH_NAMESPACE}.${BASEDOMAIN}/api/auth/gitlab/handler/frame"

# OAuth application name
APP_NAME="rhdh-exercises"

# PAT name
PAT_NAME="pat-rhdh-exercises"

# Required scopes for OAuth application
OAUTH_SCOPES="api read_user read_repository write_repository openid profile email"

# Required scopes for PAT
PAT_SCOPES="api read_api read_repository write_repository"

# Secrets file location
SECRETS_FILE="../custom-app-config-gitlab/gitlab-secrets.yaml"

echo "GitLab URL: $GITLAB_URL"
echo "Redirect URI: $REDIRECT_URI"
echo ""

# Initialize variables
CLIENT_ID=""
CLIENT_SECRET=""
PAT_TOKEN=""
NEED_SECRET_UPDATE=false

# ============================================
# Create or retrieve OAuth Application
# ============================================
echo "--- Creating OAuth Application ---"

EXISTING_APP=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "${GITLAB_URL}/api/v4/applications" | jq -r ".[] | select(.name==\"${APP_NAME}\")")

if [ -n "$EXISTING_APP" ]; then
    echo "OAuth application '${APP_NAME}' already exists."
    CLIENT_ID=$(echo "$EXISTING_APP" | jq -r '.application_id')
    echo "Existing application ID: $CLIENT_ID"
    echo "NOTE: Cannot retrieve existing secret from API."
    
    # Try to get existing secret from OpenShift
    if oc get secret gitlab-secrets -n $RHDH_NAMESPACE &>/dev/null; then
        CLIENT_SECRET=$(oc get secret gitlab-secrets -n $RHDH_NAMESPACE -o jsonpath='{.data.AUTH_GITLAB_CLIENT_SECRET}' | base64 -d 2>/dev/null)
        if [ -n "$CLIENT_SECRET" ]; then
            echo "Retrieved existing client secret from OpenShift secret."
        fi
    fi
    
    if [ -z "$CLIENT_SECRET" ]; then
        echo "WARNING: Cannot retrieve existing client secret."
        echo "If you need a new secret, delete the OAuth application first:"
        APP_ID=$(echo "$EXISTING_APP" | jq -r '.id')
        echo "  curl -X DELETE --header 'PRIVATE-TOKEN: $GITLAB_TOKEN' '${GITLAB_URL}/api/v4/applications/${APP_ID}'"
    fi
else
    echo "Creating OAuth application '${APP_NAME}'..."
    
    RESPONSE=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --data "name=${APP_NAME}" \
        --data "redirect_uri=${REDIRECT_URI}" \
        --data "scopes=${OAUTH_SCOPES}" \
        --data "confidential=false" \
        "${GITLAB_URL}/api/v4/applications")
    
    CLIENT_ID=$(echo "$RESPONSE" | jq -r '.application_id')
    CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.secret')
    
    if [ "$CLIENT_ID" = "null" ] || [ -z "$CLIENT_ID" ]; then
        echo "ERROR: Failed to create OAuth application."
        echo "Response: $RESPONSE"
        exit 1
    fi
    
    echo "OAuth application created successfully!"
    echo "Application ID: $CLIENT_ID"
    NEED_SECRET_UPDATE=true
fi

echo ""

# ============================================
# Step 2: Create or retrieve Personal Access Token (PAT)
# ============================================
echo "--- Creating Personal Access Token (PAT) ---"

# Get the root user ID
ROOT_USER_ID=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "${GITLAB_URL}/api/v4/users?username=root" | jq -r '.[0].id')

if [ "$ROOT_USER_ID" = "null" ] || [ -z "$ROOT_USER_ID" ]; then
    echo "ERROR: Could not find root user ID."
    exit 1
fi

echo "Root user ID: $ROOT_USER_ID"

# Check if PAT already exists
EXISTING_PAT=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "${GITLAB_URL}/api/v4/personal_access_tokens" | jq -r ".[] | select(.name==\"${PAT_NAME}\" and .revoked==false and .active==true)")

if [ -n "$EXISTING_PAT" ]; then
    echo "PAT '${PAT_NAME}' already exists and is active."
    
    # Try to get existing PAT from OpenShift secret
    if oc get secret gitlab-secrets -n $RHDH_NAMESPACE &>/dev/null; then
        PAT_TOKEN=$(oc get secret gitlab-secrets -n $RHDH_NAMESPACE -o jsonpath='{.data.GITLAB_TOKEN}' | base64 -d 2>/dev/null)
        if [ -n "$PAT_TOKEN" ]; then
            echo "Retrieved existing PAT from OpenShift secret."
        fi
    fi
    
    # If we need to update the secret but can't retrieve the PAT, revoke and create new
    if [ -z "$PAT_TOKEN" ] && [ "$NEED_SECRET_UPDATE" = true ]; then
        echo "Cannot retrieve existing PAT token, but need it for secret generation."
        echo "Revoking existing PAT and creating a new one..."
        
        EXISTING_PAT_ID=$(echo "$EXISTING_PAT" | jq -r '.id')
        curl $CURL_DISABLE_SSL_VERIFICATION -s --request DELETE \
            --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "${GITLAB_URL}/api/v4/personal_access_tokens/${EXISTING_PAT_ID}" &>/dev/null
        
        echo "Existing PAT revoked. Creating new PAT..."
        EXISTING_PAT=""  # Clear so we fall through to creation
    elif [ -z "$PAT_TOKEN" ]; then
        echo "NOTE: Cannot retrieve existing PAT token from API."
        echo "Using existing secret if available."
    fi
fi

# Create PAT if it doesn't exist or was revoked
if [ -z "$PAT_TOKEN" ] && ([ -z "$EXISTING_PAT" ] || [ "$NEED_SECRET_UPDATE" = true ]); then
    echo "Creating PAT '${PAT_NAME}'..."
    
    # Calculate expiration date (1 year from now)
    EXPIRES_AT=$(date -v+1y +%Y-%m-%d 2>/dev/null || date -d "+1 year" +%Y-%m-%d 2>/dev/null)
    
    RESPONSE=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"name\": \"${PAT_NAME}\", \"scopes\": [\"api\", \"read_api\", \"read_repository\", \"write_repository\"], \"expires_at\": \"${EXPIRES_AT}\"}" \
        "${GITLAB_URL}/api/v4/users/${ROOT_USER_ID}/personal_access_tokens")
    
    PAT_TOKEN=$(echo "$RESPONSE" | jq -r '.token')
    
    if [ "$PAT_TOKEN" = "null" ] || [ -z "$PAT_TOKEN" ]; then
        echo "ERROR: Failed to create PAT."
        echo "Response: $RESPONSE"
        exit 1
    fi
    
    echo "PAT created successfully!"
    NEED_SECRET_UPDATE=true
fi

echo ""

# ============================================
# Step 3: Generate and apply gitlab-secrets
# ============================================
echo "--- Creating GitLab Secrets ---"

if [ "$NEED_SECRET_UPDATE" = true ]; then
    # Validate we have all required values
    if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
        echo "ERROR: Missing CLIENT_ID for secret generation."
        exit 1
    fi
    if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" = "null" ]; then
        echo "ERROR: Missing CLIENT_SECRET for secret generation."
        exit 1
    fi
    if [ -z "$PAT_TOKEN" ] || [ "$PAT_TOKEN" = "null" ]; then
        echo "ERROR: Missing PAT_TOKEN for secret generation."
        exit 1
    fi
    
    echo "Generating ${SECRETS_FILE}..."
    
    cat > "$SECRETS_FILE" << EOF
kind: Secret
apiVersion: v1
metadata:
  name: gitlab-secrets
  namespace: ${RHDH_NAMESPACE}
stringData:
  AUTH_GITLAB_CLIENT_ID: ${CLIENT_ID}
  AUTH_GITLAB_CLIENT_SECRET: ${CLIENT_SECRET}
  GITLAB_TOKEN: ${PAT_TOKEN}
type: Opaque
EOF
    
    echo "File ${SECRETS_FILE} generated successfully!"
    
    # Apply the secret to OpenShift
    echo "Applying gitlab-secrets secret to namespace $RHDH_NAMESPACE..."
    oc apply -f "$SECRETS_FILE" -n $RHDH_NAMESPACE
    
    if [ $? -eq 0 ]; then
        echo "Secret 'gitlab-secrets' created/updated successfully!"
    else
        echo "ERROR: Failed to create/update secret."
        exit 1
    fi
else
    echo "No changes needed for gitlab-secrets."
    
    # Verify secret exists
    if ! oc get secret gitlab-secrets -n $RHDH_NAMESPACE &>/dev/null; then
        echo "WARNING: Secret 'gitlab-secrets' does not exist but OAuth app and PAT already exist."
        echo "Please delete the OAuth application and PAT, then re-run this script."
    fi
fi

echo ""
echo "=============================================="
echo "GitLab authentication & integration complete!"
echo "=============================================="
echo ""
echo "The following have been configured:"
echo "  - OAuth Application: ${APP_NAME}"
echo "  - Personal Access Token: ${PAT_NAME}"
echo "  - Secret: gitlab-secrets (in namespace ${RHDH_NAMESPACE})"
echo "  - Generated file: ${SECRETS_FILE}"
echo ""
echo ""
