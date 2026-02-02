#!/bin/bash

# Common functions and utilities for RHDH Workshop scripts
# Source this file at the beginning of each script:
#   source "$(dirname "$0")/common.sh"

# Exit on error and catch pipeline failures
set -e
set -o pipefail

# Track script start time for duration reporting
SCRIPT_START_TIME=$(date +%s)

# Change to script directory
cd "$(dirname "$0")"

# Source configuration
source ./config.env

# ============================================
# Logging Functions
# ============================================

# Get current timestamp for log messages
get_timestamp() {
    date '+%H:%M:%S'
}

# Get elapsed time since script start
get_elapsed_time() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - SCRIPT_START_TIME))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    printf "%dm %ds" $mins $secs
}

log_info() {
    echo "[$(get_timestamp)] [INFO] $1"
}

log_ok() {
    echo "[$(get_timestamp)] [OK] $1"
}

log_skip() {
    echo "[$(get_timestamp)] [SKIP] $1"
}

log_wait() {
    echo "[$(get_timestamp)] [WAIT] $1"
}

log_warn() {
    echo "[$(get_timestamp)] [WARN] $1"
}

log_error() {
    echo "[$(get_timestamp)] [ERROR] $1" >&2
}

# ============================================
# Argument Parsing
# ============================================

# Global variable for SSL verification
CURL_DISABLE_SSL_VERIFICATION=""
ssl_certs_self_signed="n"

parse_ssl_arg() {
    for arg in "$@"; do
        case $arg in
            --ssl_certs_self_signed=*)
                ssl_certs_self_signed="${arg#*=}"
                if [ "$ssl_certs_self_signed" = "y" ]; then
                    log_info "SSL Certificates self signed enabled."
                    CURL_DISABLE_SSL_VERIFICATION="-k"
                fi
                ;;
        esac
    done
}

# ============================================
# CLI Requirement Checks
# ============================================

require_cli() {
    local cmd=$1
    local name=${2:-$1}
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "$name is required but not installed. Aborting."
        exit 1
    fi
}

check_required_clis() {
    require_cli "oc" "OpenShift CLI (oc)"
    require_cli "jq" "jq"
    require_cli "envsubst" "envsubst"
}

check_basic_clis() {
    require_cli "oc" "OpenShift CLI (oc)"
    require_cli "jq" "jq"
}

# ============================================
# Environment Detection
# ============================================

get_basedomain() {
    local basedomain
    basedomain=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}' 2>/dev/null)
    if [ -z "$basedomain" ]; then
        log_error "Could not get base domain. Make sure you are logged in to OpenShift."
        exit 1
    fi
    echo "$basedomain"
}

get_gitlab_url() {
    local gitlab_url
    gitlab_url="https://$(oc get ingress -n "$GITLAB_NAMESPACE" -l app=webservice -o jsonpath='{ .items[*].spec.rules[*].host }')"
    echo "$gitlab_url"
}

get_basedomain_from_gitlab() {
    oc get ingress -n "$GITLAB_NAMESPACE" -l app=webservice -o jsonpath='{ .items[*].spec.rules[*].host }' | sed 's/^gitlab\.//'
}

# ============================================
# GitLab Token Handling
# ============================================

# Create a PAT via GitLab Rails console (works with fresh GitLab installations)
create_gitlab_pat_via_rails() {
    local pat_name=${1:-"automation-token"}
    local toolbox_pod

    # Find the GitLab toolbox pod
    toolbox_pod=$(oc get pods -n "$GITLAB_NAMESPACE" -l app=toolbox -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$toolbox_pod" ]; then
        log_error "Could not find GitLab toolbox pod in namespace $GITLAB_NAMESPACE"
        return 1
    fi

    # Use stderr for log message to avoid polluting the token output
    echo "[INFO] Creating PAT via GitLab Rails console (pod: $toolbox_pod)..." >&2

    # Create PAT via Rails console and capture the token
    local pat_token
    pat_token=$(oc exec -n "$GITLAB_NAMESPACE" "$toolbox_pod" -- gitlab-rails runner "
user = User.find_by(username: 'root')
if user.nil?
  puts 'ERROR: root user not found'
  exit 1
end

# Check for existing token with this name
existing = user.personal_access_tokens.find_by(name: '${pat_name}', revoked: false)
if existing && !existing.expired?
  # Revoke existing token so we can create a new one with a retrievable value
  existing.revoke!
end

token = user.personal_access_tokens.create!(
  name: '${pat_name}',
  scopes: [:api, :read_api, :read_user, :read_repository, :write_repository],
  expires_at: 1.year.from_now
)
puts token.token
" 2>/dev/null)

    # Check if we got a valid token (starts with glpat- or is a valid format)
    if [ -z "$pat_token" ] || [[ "$pat_token" == *"ERROR"* ]]; then
        log_error "Failed to create PAT via Rails console"
        return 1
    fi

    # Clean up any whitespace
    pat_token=$(echo "$pat_token" | tr -d '[:space:]')

    echo "$pat_token"
    return 0
}

get_gitlab_token() {
    # If GITLAB_TOKEN is already set in environment, use it
    if [ -n "$GITLAB_TOKEN" ]; then
        echo "$GITLAB_TOKEN"
        return 0
    fi

    # Try to get existing PAT from gitlab-secrets (if it exists)
    local pat_token
    pat_token=$(oc get secret gitlab-secrets -n "$RHDH_NAMESPACE" -o jsonpath='{.data.GITLAB_TOKEN}' 2>/dev/null | base64_decode || echo "")
    if [ -n "$pat_token" ]; then
        echo "[INFO] Using existing PAT from gitlab-secrets" >&2
        echo "$pat_token"
        return 0
    fi

    # Try to get from a dedicated automation secret (created by this script)
    pat_token=$(oc get secret gitlab-automation-pat -n "$GITLAB_NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64_decode || echo "")
    if [ -n "$pat_token" ]; then
        echo "[INFO] Using existing PAT from gitlab-automation-pat secret" >&2
        echo "$pat_token"
        return 0
    fi

    # Create a new PAT via Rails console
    echo "[INFO] No existing GitLab PAT found. Creating one via Rails console..." >&2
    pat_token=$(create_gitlab_pat_via_rails "automation-pat-rhdh")

    if [ -n "$pat_token" ]; then
        # Store the PAT in a secret for future use
        echo "[INFO] Storing PAT in gitlab-automation-pat secret for future runs..." >&2
        oc create secret generic gitlab-automation-pat \
            --from-literal=token="$pat_token" \
            -n "$GITLAB_NAMESPACE" \
            --dry-run=client -o yaml | oc apply -f - >/dev/null 2>&1

        echo "$pat_token"
        return 0
    fi

    log_error "Could not obtain a GitLab token."
    log_error "Please set GITLAB_TOKEN environment variable with a valid PAT:"
    log_error "  export GITLAB_TOKEN=<your-gitlab-admin-token>"
    exit 1
}

# ============================================
# Base64 Encoding/Decoding (Cross-platform)
# ============================================

base64_encode() {
    echo -n "$1" | base64 -w0 2>/dev/null || echo -n "$1" | base64
}

base64_decode() {
    base64 -d 2>/dev/null || base64 -D 2>/dev/null
}

# ============================================
# Generic Wait Function
# ============================================

# wait_for_condition: Generic polling function
# Arguments:
#   $1 - description: Human-readable description of what we're waiting for
#   $2 - check_cmd: Command to run (should output the current status)
#   $3 - expected: Expected value to match
#   $4 - timeout: Maximum wait time in seconds (default: 300)
#   $5 - interval: Polling interval in seconds (default: 10)
#   $6 - match_type: "exact" (default), "contains", or "minimum" (for numeric comparisons)
# Returns:
#   0 on success, 1 on timeout
wait_for_condition() {
    local description=$1
    local check_cmd=$2
    local expected=$3
    local timeout=${4:-$DEFAULT_TIMEOUT}
    local interval=${5:-$DEFAULT_POLL_INTERVAL}
    local match_type=${6:-exact}
    local elapsed=0

    log_wait "$description (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        local current
        current=$(eval "$check_cmd" 2>/dev/null || echo "")

        local matched=false
        case $match_type in
            exact)
                [ "$current" = "$expected" ] && matched=true
                ;;
            contains)
                echo "$current" | grep -q "$expected" && matched=true
                ;;
            minimum)
                [ -n "$current" ] && [ "$current" -ge "$expected" ] 2>/dev/null && matched=true
                ;;
        esac

        if [ "$matched" = true ]; then
            log_ok "$description - Ready!"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
        echo "  Status: ${current:-pending} (${elapsed}s/${timeout}s)"
    done

    log_error "Timeout waiting for: $description"
    return 1
}

# ============================================
# Specialized Wait Functions (using generic wait)
# ============================================

wait_for_csv() {
    local namespace=$1
    local csv_prefix=$2
    local timeout=${3:-$DEFAULT_TIMEOUT}

    wait_for_condition \
        "CSV ${csv_prefix}* in namespace ${namespace}" \
        "oc get csv -n '$namespace' -o jsonpath='{.items[?(@.metadata.name)].status.phase}' | grep -o 'Succeeded' | head -1" \
        "Succeeded" \
        "$timeout" \
        "$DEFAULT_POLL_INTERVAL" \
        "exact"
}

wait_for_gitlab() {
    local timeout=${1:-$GITLAB_TIMEOUT}

    wait_for_condition \
        "GitLab to be running" \
        "oc get gitlabs gitlab -o jsonpath='{.status.phase}' -n '$GITLAB_NAMESPACE'" \
        "Running" \
        "$timeout" \
        "$LONG_POLL_INTERVAL" \
        "exact"
}

wait_for_rhdh() {
    local timeout=${1:-$DEFAULT_TIMEOUT}

    wait_for_condition \
        "RHDH to be deployed" \
        "oc get backstage developer-hub -o jsonpath='{.status.conditions[0].type}' -n '$RHDH_NAMESPACE'" \
        "Deployed" \
        "$timeout" \
        15 \
        "exact"
}

wait_for_odf_operator() {
    local timeout=${1:-$ODF_OPERATOR_TIMEOUT}
    local required=5
    local elapsed=0

    log_wait "ODF operators (${required}+ CSVs to Succeed) (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        local succeeded=0

        if oc get csv -n openshift-storage &>/dev/null; then
            succeeded=$(oc get csv -n openshift-storage -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o 'Succeeded' | wc -l | tr -d '[:space:]' || echo 0)
            # Ensure clean integer
            succeeded=$(echo "$succeeded" | tr -d '\n' | head -1)
            [ -z "$succeeded" ] && succeeded=0
        fi

        # Debug output if enabled
        if [ "${DEBUG:-}" = "1" ]; then
            echo "  DEBUG: raw_succeeded='$succeeded'"
        fi

        if [ "$succeeded" -ge "$required" ] 2>/dev/null; then
            echo "  Status: ${succeeded}/${required} successfully finished"
            log_ok "ODF operators - ${succeeded} CSVs Succeeded"
            return 0
        fi

        sleep "$LONG_POLL_INTERVAL"
        elapsed=$((elapsed + LONG_POLL_INTERVAL))
        echo "  Status: ${succeeded}/${required} in progress (${elapsed}s/${timeout}s)"
    done

    log_error "Timeout waiting for ODF operators"
    return 1
}

wait_for_storage_cluster() {
    local timeout=${1:-$STORAGE_CLUSTER_TIMEOUT}

    # Note: ODF storage cluster may briefly show "Error" status during initial provisioning
    # before transitioning to "Progressing" and finally "Ready". This is expected behavior.
    log_info "Note: 'Error' status during initial setup is normal and will resolve automatically."

    wait_for_condition \
        "ODF storage cluster (may take 10-20 minutes)" \
        "oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}'" \
        "Ready" \
        "$timeout" \
        "$STORAGE_POLL_INTERVAL" \
        "exact"
}

wait_for_crd() {
    local crd_name=$1
    local timeout=${2:-$DEFAULT_TIMEOUT}

    wait_for_condition \
        "CRD $crd_name to be available" \
        "oc get crd '$crd_name' -o name 2>/dev/null && echo 'exists'" \
        "exists" \
        "$timeout" \
        "$DEFAULT_POLL_INTERVAL" \
        "contains"
}

# ============================================
# Version File Helper
# ============================================

# Find the latest versioned file matching a prefix
# Usage: find_latest_version "rhdh-app-configmap" "../custom-app-config-gitlab"
find_latest_version() {
    local prefix=$1
    local dir=$2

    ls -1 "${dir}/${prefix}"-*.yaml 2>/dev/null | \
        sed 's/.*-\([0-9]*\)\.yaml/\1 &/' | \
        sort -rn | \
        head -1 | \
        cut -d' ' -f2
}

# ============================================
# OpenShift Resource Helpers
# ============================================

# Check if a resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-}

    if [ -n "$namespace" ]; then
        oc get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null
    else
        oc get "$resource_type" "$resource_name" &>/dev/null
    fi
}

# Check if an operator is installed (CSV exists or operator pods running)
operator_installed() {
    local namespace=$1

    # Check if namespace exists and has any CSV (succeeded or not)
    if oc get csv -n "$namespace" --no-headers 2>/dev/null | grep -q .; then
        return 0
    fi

    # Also check for running operator pods (for cases where CSV is in bad state but operator works)
    if oc get pods -n "$namespace" --no-headers 2>/dev/null | grep -q "Running"; then
        return 0
    fi

    return 1
}

# Apply a file with optional namespace
apply_resource() {
    local file=$1
    local namespace=${2:-}

    if [ ! -f "$file" ]; then
        log_warn "File not found: $file"
        return 1
    fi

    log_info "Applying $(basename "$file")..."
    if [ -n "$namespace" ]; then
        oc apply -f "$file" -n "$namespace"
    else
        oc apply -f "$file"
    fi
    sleep 2
}

# Apply a file with envsubst
apply_resource_envsubst() {
    local file=$1
    local namespace=${2:-}

    if [ ! -f "$file" ]; then
        log_warn "File not found: $file"
        return 1
    fi

    log_info "Applying $(basename "$file") (with envsubst)..."
    if [ -n "$namespace" ]; then
        envsubst < "$file" | oc apply -n "$namespace" -f -
    else
        envsubst < "$file" | oc apply -f -
    fi
}

# ============================================
# GitLab API Helpers
# ============================================

gitlab_api_get() {
    local endpoint=$1
    local token=$2
    local gitlab_url=$3
    local response

    response=$(curl $CURL_DISABLE_SSL_VERIFICATION -s \
        --header "PRIVATE-TOKEN: $token" \
        "${gitlab_url}${endpoint}")

    # Check if response is valid JSON
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        log_error "GitLab API returned invalid JSON for $endpoint"
        log_error "Response: $(echo "$response" | head -c 200)"
        echo "[]"  # Return empty array to prevent jq errors
        return 1
    fi

    # Check for API error messages
    local error_msg
    error_msg=$(echo "$response" | jq -r '.message // .error // empty' 2>/dev/null)
    if [ -n "$error_msg" ]; then
        log_error "GitLab API error for $endpoint: $error_msg"
        echo "[]"
        return 1
    fi

    echo "$response"
}

gitlab_api_post() {
    local endpoint=$1
    local token=$2
    local gitlab_url=$3
    shift 3
    local response

    response=$(curl $CURL_DISABLE_SSL_VERIFICATION -s --request POST \
        --header "PRIVATE-TOKEN: $token" \
        "$@" \
        "${gitlab_url}${endpoint}")

    # Check if response is valid JSON
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        log_error "GitLab API POST returned invalid JSON for $endpoint"
        log_error "Response: $(echo "$response" | head -c 200)"
        echo "{}"
        return 1
    fi

    echo "$response"
}

gitlab_api_put() {
    local endpoint=$1
    local token=$2
    local gitlab_url=$3
    shift 3

    curl $CURL_DISABLE_SSL_VERIFICATION -s --request PUT \
        --header "PRIVATE-TOKEN: $token" \
        "$@" \
        "${gitlab_url}${endpoint}"
}

gitlab_api_delete() {
    local endpoint=$1
    local token=$2
    local gitlab_url=$3

    curl $CURL_DISABLE_SSL_VERIFICATION -s --request DELETE \
        --header "PRIVATE-TOKEN: $token" \
        "${gitlab_url}${endpoint}"
}

# Set or update a GitLab CI/CD variable
set_gitlab_variable() {
    local key=$1
    local value=$2
    local token=$3
    local gitlab_url=$4
    local protected=${5:-false}
    local masked=${6:-false}

    # Check if variable already exists (directly with curl to avoid error logging)
    local response
    response=$(curl $CURL_DISABLE_SSL_VERIFICATION -s \
        --header "PRIVATE-TOKEN: $token" \
        "${gitlab_url}/api/v4/admin/ci/variables/${key}")

    # Check if response contains the key (variable exists) or is an error
    local existing
    existing=$(echo "$response" | jq -r '.key // empty' 2>/dev/null)

    if [ -n "$existing" ] && [ "$existing" = "$key" ]; then
        log_info "Updating CI/CD variable: $key"
        gitlab_api_put "/api/v4/admin/ci/variables/${key}" "$token" "$gitlab_url" \
            --form "value=${value}" \
            --form "protected=${protected}" \
            --form "masked=${masked}" \
            --form "raw=true" &>/dev/null
    else
        log_info "Creating CI/CD variable: $key"
        gitlab_api_post "/api/v4/admin/ci/variables" "$token" "$gitlab_url" \
            --form "key=${key}" \
            --form "value=${value}" \
            --form "protected=${protected}" \
            --form "masked=${masked}" \
            --form "raw=true" &>/dev/null
    fi
}

# ============================================
# Secret Helpers
# ============================================

get_secret_value() {
    local secret_name=$1
    local key=$2
    local namespace=$3

    oc get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.$key}" 2>/dev/null | base64_decode
}

patch_secret() {
    local secret_name=$1
    local key=$2
    local value=$3
    local namespace=$4

    local value_b64
    value_b64=$(base64_encode "$value")
    oc patch secret "$secret_name" -n "$namespace" -p '{"data":{"'"$key"'":"'"$value_b64"'"}}'
}

# ============================================
# Cleanup Trap (optional - call setup_cleanup_trap to enable)
# ============================================

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
        log_error "Check the output above for details."
    fi
}

setup_cleanup_trap() {
    trap cleanup_on_error EXIT
}

# ============================================
# Print Banner
# ============================================

print_banner() {
    local title=$1
    echo ""
    echo "=============================================="
    echo "  $title"
    echo "=============================================="
    echo ""
}

print_section() {
    local title=$1
    echo ""
    echo "=== $title ==="
}
