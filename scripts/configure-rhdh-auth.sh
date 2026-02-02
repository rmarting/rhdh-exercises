#!/bin/bash

# Post-configure GitLab for RHDH authentication
# This script creates a GitLab OAuth application, a Personal Access Token (PAT),
# and creates the gitlab-secrets Kubernetes secret.

# Source common functions
source "$(dirname "$0")/common.sh"

# Parse SSL argument
parse_ssl_arg "$@"

# Check required CLI's
check_basic_clis

# Get GitLab token (will exit if not available)
GITLAB_TOKEN=$(get_gitlab_token)

# Get URLs
GITLAB_URL=$(get_gitlab_url)
BASEDOMAIN=$(get_basedomain_from_gitlab)

# RHDH redirect URI for OAuth
REDIRECT_URI="https://backstage-developer-hub-${RHDH_NAMESPACE}.${BASEDOMAIN}/api/auth/gitlab/handler/frame"

log_info "GitLab URL: $GITLAB_URL"
log_info "Redirect URI: $REDIRECT_URI"
echo ""

# Initialize variables
CLIENT_ID=""
CLIENT_SECRET=""
PAT_TOKEN=""
NEED_SECRET_UPDATE=false

# ============================================
# Create or retrieve OAuth Application
# ============================================
print_section "Creating OAuth Application"

EXISTING_APP=$(gitlab_api_get "/api/v4/applications" "$GITLAB_TOKEN" "$GITLAB_URL" | \
    jq -r ".[] | select(.name==\"${OAUTH_APP_NAME}\")")

if [ -n "$EXISTING_APP" ]; then
    log_skip "OAuth application '${OAUTH_APP_NAME}' already exists."
    CLIENT_ID=$(echo "$EXISTING_APP" | jq -r '.application_id')
    log_info "Existing application ID: $CLIENT_ID"
    log_info "NOTE: Cannot retrieve existing secret from API."

    # Try to get existing secret from OpenShift
    if resource_exists "secret" "gitlab-secrets" "$RHDH_NAMESPACE"; then
        CLIENT_SECRET=$(get_secret_value "gitlab-secrets" "AUTH_GITLAB_CLIENT_SECRET" "$RHDH_NAMESPACE")
        if [ -n "$CLIENT_SECRET" ]; then
            log_ok "Retrieved existing client secret from OpenShift secret."
        fi
    fi

    if [ -z "$CLIENT_SECRET" ]; then
        log_warn "Cannot retrieve existing client secret."
        log_info "If you need a new secret, delete the OAuth application first:"
        APP_ID=$(echo "$EXISTING_APP" | jq -r '.id')
        echo "  curl -X DELETE --header 'PRIVATE-TOKEN: \$GITLAB_TOKEN' '${GITLAB_URL}/api/v4/applications/${APP_ID}'"
    fi
else
    log_info "Creating OAuth application '${OAUTH_APP_NAME}'..."

    RESPONSE=$(gitlab_api_post "/api/v4/applications" "$GITLAB_TOKEN" "$GITLAB_URL" \
        --data "name=${OAUTH_APP_NAME}" \
        --data "redirect_uri=${REDIRECT_URI}" \
        --data "scopes=${OAUTH_SCOPES}" \
        --data "confidential=false")

    CLIENT_ID=$(echo "$RESPONSE" | jq -r '.application_id')
    CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.secret')

    if [ "$CLIENT_ID" = "null" ] || [ -z "$CLIENT_ID" ]; then
        log_error "Failed to create OAuth application."
        log_error "Response: $RESPONSE"
        exit 1
    fi

    log_ok "OAuth application created successfully!"
    log_info "Application ID: $CLIENT_ID"
    NEED_SECRET_UPDATE=true
fi

echo ""

# ============================================
# Step 2: Create or retrieve Personal Access Token (PAT)
# ============================================
print_section "Creating Personal Access Token (PAT)"

# Get the root user ID
ROOT_USER_ID=$(gitlab_api_get "/api/v4/users?username=root" "$GITLAB_TOKEN" "$GITLAB_URL" | jq -r '.[0].id')

if [ "$ROOT_USER_ID" = "null" ] || [ -z "$ROOT_USER_ID" ]; then
    log_error "Could not find root user ID."
    exit 1
fi

log_info "Root user ID: $ROOT_USER_ID"

# Check if PAT already exists
EXISTING_PAT=$(gitlab_api_get "/api/v4/personal_access_tokens" "$GITLAB_TOKEN" "$GITLAB_URL" | \
    jq -r ".[] | select(.name==\"${PAT_NAME}\" and .revoked==false and .active==true)")

if [ -n "$EXISTING_PAT" ]; then
    log_skip "PAT '${PAT_NAME}' already exists and is active."

    # Try to get existing PAT from OpenShift secret
    if resource_exists "secret" "gitlab-secrets" "$RHDH_NAMESPACE"; then
        PAT_TOKEN=$(get_secret_value "gitlab-secrets" "GITLAB_TOKEN" "$RHDH_NAMESPACE")
        if [ -n "$PAT_TOKEN" ]; then
            log_ok "Retrieved existing PAT from OpenShift secret."
        fi
    fi

    # If we need to update the secret but can't retrieve the PAT, revoke and create new
    if [ -z "$PAT_TOKEN" ] && [ "$NEED_SECRET_UPDATE" = true ]; then
        log_info "Cannot retrieve existing PAT token, but need it for secret generation."
        log_info "Revoking existing PAT and creating a new one..."

        EXISTING_PAT_ID=$(echo "$EXISTING_PAT" | jq -r '.id')
        gitlab_api_delete "/api/v4/personal_access_tokens/${EXISTING_PAT_ID}" "$GITLAB_TOKEN" "$GITLAB_URL" &>/dev/null

        log_info "Existing PAT revoked. Creating new PAT..."
        EXISTING_PAT=""  # Clear so we fall through to creation
    elif [ -z "$PAT_TOKEN" ]; then
        log_info "NOTE: Cannot retrieve existing PAT token from API."
        log_info "Using existing secret if available."
    fi
fi

# Create PAT if it doesn't exist or was revoked
if [ -z "$PAT_TOKEN" ] && ([ -z "$EXISTING_PAT" ] || [ "$NEED_SECRET_UPDATE" = true ]); then
    log_info "Creating PAT '${PAT_NAME}'..."

    # Calculate expiration date (1 year from now)
    EXPIRES_AT=$(date -v+1y +%Y-%m-%d 2>/dev/null || date -d "+1 year" +%Y-%m-%d 2>/dev/null)

    RESPONSE=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data @- \
        "${GITLAB_URL}/api/v4/users/${ROOT_USER_ID}/personal_access_tokens" <<EOF
{
    "name": "${PAT_NAME}",
    "scopes": ["api", "read_api", "read_repository", "write_repository"],
    "expires_at": "${EXPIRES_AT}"
}
EOF
    )

    PAT_TOKEN=$(echo "$RESPONSE" | jq -r '.token')

    if [ "$PAT_TOKEN" = "null" ] || [ -z "$PAT_TOKEN" ]; then
        log_error "Failed to create PAT."
        log_error "Response: $RESPONSE"
        exit 1
    fi

    log_ok "PAT created successfully!"
    NEED_SECRET_UPDATE=true
fi

echo ""

# ============================================
# Step 3: Generate and apply gitlab-secrets
# ============================================
print_section "Creating GitLab Secrets"

if [ "$NEED_SECRET_UPDATE" = true ]; then
    # Validate we have all required values
    if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
        log_error "Missing CLIENT_ID for secret generation."
        exit 1
    fi
    if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" = "null" ]; then
        log_error "Missing CLIENT_SECRET for secret generation."
        exit 1
    fi
    if [ -z "$PAT_TOKEN" ] || [ "$PAT_TOKEN" = "null" ]; then
        log_error "Missing PAT_TOKEN for secret generation."
        exit 1
    fi

    log_info "Generating ${SECRETS_FILE}..."

    cat > "$SECRETS_FILE" <<EOF
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

    log_ok "File ${SECRETS_FILE} generated successfully!"

    # Apply the secret to OpenShift
    log_info "Applying gitlab-secrets secret to namespace $RHDH_NAMESPACE..."
    oc apply -f "$SECRETS_FILE" -n "$RHDH_NAMESPACE"

    if [ $? -eq 0 ]; then
        log_ok "Secret 'gitlab-secrets' created/updated successfully!"
    else
        log_error "Failed to create/update secret."
        exit 1
    fi
else
    log_skip "No changes needed for gitlab-secrets."

    # Verify secret exists
    if ! resource_exists "secret" "gitlab-secrets" "$RHDH_NAMESPACE"; then
        log_warn "Secret 'gitlab-secrets' does not exist but OAuth app and PAT already exist."
        log_info "Please delete the OAuth application and PAT, then re-run this script."
    fi
fi

print_banner "GitLab Authentication Complete!"

echo "The following have been configured:"
echo "  - OAuth Application: ${OAUTH_APP_NAME}"
echo "  - Personal Access Token: ${PAT_NAME}"
echo "  - Secret: gitlab-secrets (in namespace ${RHDH_NAMESPACE})"
echo "  - Generated file: ${SECRETS_FILE}"
echo ""
