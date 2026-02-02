#!/bin/bash

# Autosetup script for RHDH Workshop
# This script automates the complete setup of the workshop environment:
# 1. README-preparation.md steps (operators, GitLab, RHDH)
# 2. configure-rhdh-auth.sh (OAuth app, PAT, secrets)
# 3. Latest version of all resource YAMLs

# Source common functions
source "$(dirname "$0")/common.sh"

# Enable cleanup trap
setup_cleanup_trap

# ============================================
# Command-line Arguments
# ============================================
SKIP_OPERATORS="n"
SKIP_GITLAB="n"
SKIP_RHDH_OPERATOR="n"
SKIP_ODF="n"
SKIP_TECHDOCS="n"
SKIP_ORCHESTRATOR="n"
SKIP_LIGHTSPEED="n"
PARALLEL_OPERATORS="y"  # Enable parallel operator installation by default

for arg in "$@"; do
    case $arg in
        --ssl_certs_self_signed=*)
            ssl_certs_self_signed="${arg#*=}"
            if [ "$ssl_certs_self_signed" = "y" ]; then
                log_info "SSL Certificates self signed enabled."
                CURL_DISABLE_SSL_VERIFICATION="-k"
            fi
            ;;
        --skip-operators)
            SKIP_OPERATORS="y"
            ;;
        --skip-gitlab)
            SKIP_GITLAB="y"
            ;;
        --skip-rhdh-operator)
            SKIP_RHDH_OPERATOR="y"
            ;;
        --skip-odf)
            SKIP_ODF="y"
            ;;
        --skip-techdocs)
            SKIP_TECHDOCS="y"
            ;;
        --skip-orchestrator)
            SKIP_ORCHESTRATOR="y"
            ;;
        --skip-lightspeed)
            SKIP_LIGHTSPEED="y"
            ;;
        --sequential-operators)
            PARALLEL_OPERATORS="n"
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --ssl_certs_self_signed=y  Enable SSL verification bypass for self-signed certs"
            echo "  --skip-operators           Skip operator installations (cert-manager, gitlab, rhdh)"
            echo "  --skip-gitlab              Skip GitLab deployment and configuration"
            echo "  --skip-rhdh-operator       Skip RHDH operator installation"
            echo "  --skip-odf                 Skip OpenShift Data Foundation installation"
            echo "  --skip-techdocs            Skip TechDocs setup (ODF, bucket, GitLab runner)"
            echo "  --skip-orchestrator        Skip Orchestrator/Serverless Logic Operator installation"
            echo "  --skip-lightspeed          Skip Lightspeed secret configuration"
            echo "  --sequential-operators     Install operators sequentially instead of in parallel"
            echo "  --help                     Show this help message"
            echo ""
            echo "Environment variables for Lightspeed (Red Hat Demo Platform MaaS):"
            echo "  VLLM_URL                   LLM service endpoint URL"
            echo "  VLLM_API_KEY               LLM service API key"
            echo "  VALIDATION_MODEL_NAME      Model name (e.g., meta-llama/Llama-3.3-70B-Instruct)"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check required CLI's
check_required_clis

# Get base domain
export BASEDOMAIN=$(get_basedomain)
log_info "Base Domain: $BASEDOMAIN"

print_banner "RHDH Workshop Auto Setup"

# ============================================
# Parallel Operator Installation Function
# ============================================
install_operators_parallel() {
    local pids=()
    local operator_results=()

    # Start cert-manager operator installation in background
    if [ "$SKIP_OPERATORS" != "y" ]; then
        if operator_installed "cert-manager-operator"; then
            log_skip "cert-manager operator already installed"
        else
            log_info "Installing cert-manager operator (background)..."
            (
                oc apply -f ../lab-prep/cert-manager-operator.yaml
                wait_for_csv "cert-manager-operator" "cert-manager-operator"
            ) &
            pids+=($!)
            operator_results+=("cert-manager")
        fi
    fi

    # Start GitLab operator installation in background
    if [ "$SKIP_OPERATORS" != "y" ] && [ "$SKIP_GITLAB" != "y" ]; then
        if operator_installed "gitlab-system"; then
            log_skip "GitLab operator already installed"
        else
            log_info "Installing GitLab operator (background)..."
            (
                oc apply -f ../lab-prep/gitlab-operator.yaml
                wait_for_csv "gitlab-system" "gitlab-operator"
            ) &
            pids+=($!)
            operator_results+=("gitlab")
        fi
    fi

    # Start RHDH operator installation in background
    if [ "$SKIP_OPERATORS" != "y" ] && [ "$SKIP_RHDH_OPERATOR" != "y" ]; then
        if operator_installed "rhdh-operator"; then
            log_skip "RHDH operator already installed"
        else
            log_info "Installing RHDH operator (background)..."
            (
                oc apply -f ../lab-prep/rhdh-operator.yaml
                wait_for_csv "rhdh-operator" "rhdh-operator"
            ) &
            pids+=($!)
            operator_results+=("rhdh")
        fi
    fi

    # Wait for all background operator installations
    if [ ${#pids[@]} -gt 0 ]; then
        log_wait "Waiting for ${#pids[@]} operator(s) to be ready..."
        local failed=0
        for i in "${!pids[@]}"; do
            if wait "${pids[$i]}"; then
                log_ok "${operator_results[$i]} operator ready"
            else
                log_error "${operator_results[$i]} operator installation failed"
                failed=$((failed + 1))
            fi
        done

        if [ $failed -gt 0 ]; then
            log_error "$failed operator(s) failed to install"
            exit 1
        fi
    fi
}

# ============================================
# Sequential Operator Installation (fallback)
# ============================================
install_operators_sequential() {
    # Step 1: Install cert-manager operator
    if [ "$SKIP_OPERATORS" != "y" ]; then
        print_section "Step 1: Install cert-manager operator"

        if operator_installed "cert-manager-operator"; then
            log_skip "cert-manager operator already installed"
        else
            log_info "Installing cert-manager operator..."
            oc apply -f ../lab-prep/cert-manager-operator.yaml
            wait_for_csv "cert-manager-operator" "cert-manager-operator"
        fi
    fi

    # Step 2: Install GitLab operator
    if [ "$SKIP_OPERATORS" != "y" ] && [ "$SKIP_GITLAB" != "y" ]; then
        print_section "Step 2: Install GitLab operator"

        if operator_installed "gitlab-system"; then
            log_skip "GitLab operator already installed"
        else
            log_info "Installing GitLab operator..."
            oc apply -f ../lab-prep/gitlab-operator.yaml
            wait_for_csv "gitlab-system" "gitlab-operator"
        fi
    fi

    # Step 5: Install RHDH operator
    if [ "$SKIP_OPERATORS" != "y" ] && [ "$SKIP_RHDH_OPERATOR" != "y" ]; then
        print_section "Step 5: Install RHDH operator"

        if operator_installed "rhdh-operator"; then
            log_skip "RHDH operator already installed"
        else
            log_info "Installing RHDH operator..."
            oc apply -f ../lab-prep/rhdh-operator.yaml
            wait_for_csv "rhdh-operator" "rhdh-operator"
        fi
    fi
}

# ============================================
# Main Installation Flow
# ============================================

# Install operators (parallel or sequential)
if [ "$PARALLEL_OPERATORS" = "y" ]; then
    print_section "Installing Operators (Parallel)"
    install_operators_parallel
else
    install_operators_sequential
fi

# ============================================
# Step 3: Deploy GitLab
# ============================================
if [ "$SKIP_GITLAB" != "y" ]; then
    print_section "Deploy GitLab"

    GITLAB_STATUS=$(oc get gitlabs gitlab -o jsonpath='{.status.phase}' -n "$GITLAB_NAMESPACE" 2>/dev/null || echo "")
    if [ "$GITLAB_STATUS" = "Running" ]; then
        log_skip "GitLab already running"
    else
        log_info "Deploying GitLab..."
        apply_resource_envsubst "../lab-prep/gitlab.yaml"
        wait_for_gitlab
    fi
fi

# ============================================
# Step 4: Configure GitLab (users, groups, repos)
# ============================================
if [ "$SKIP_GITLAB" != "y" ]; then
    print_section "Configure GitLab"

    if [ "$ssl_certs_self_signed" = "y" ]; then
        ../lab-prep/configure-gitlab.sh --ssl_certs_self_signed=y
    else
        ../lab-prep/configure-gitlab.sh
    fi
fi

# ============================================
# Step 6: Install initial RHDH instance
# ============================================
print_section "Install initial RHDH instance"

RHDH_STATUS=$(oc get backstage developer-hub -o jsonpath='{.status.conditions[0].type}' -n "$RHDH_NAMESPACE" 2>/dev/null || echo "")
if [ "$RHDH_STATUS" = "Deployed" ]; then
    log_skip "RHDH already deployed"
else
    log_info "Deploying initial RHDH instance..."
    apply_resource "../lab-prep/rhdh-instance.yaml"
    wait_for_rhdh
fi

# ============================================
# Step 7: Configure GitLab OAuth and PAT
# ============================================
print_section "Configure GitLab OAuth and PAT"

if [ "$ssl_certs_self_signed" = "y" ]; then
    ./configure-rhdh-auth.sh --ssl_certs_self_signed=y
else
    ./configure-rhdh-auth.sh
fi

# ============================================
# Step 8: Apply latest resource configurations
# ============================================
print_section "Apply latest resource configurations"

# ============================================
# Orchestrator (OpenShift Serverless Logic)
# ============================================
if [ "$SKIP_ORCHESTRATOR" != "y" ]; then

    LOGIC_CSV_STATUS=$(oc get csv -n openshift-serverless-logic -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Succeeded" | head -1 || echo "")

    if [ "$LOGIC_CSV_STATUS" = "Succeeded" ]; then
        log_skip "OpenShift Serverless Logic Operator already installed"
    else
        log_info "Installing OpenShift Serverless Logic Operator..."
        apply_resource "../lab-prep/logic-operator-rhel8-operator.yaml"
        wait_for_csv "openshift-serverless-logic" "logic-operator"
    fi
else
    log_skip "Orchestrator installation (--skip-orchestrator flag set)"
fi

# Apply rhdh-secrets (generated by configure-rhdh-auth.sh)
if [ -f "${CONFIG_DIR}/gitlab-secrets.yaml" ]; then
    apply_resource "${CONFIG_DIR}/gitlab-secrets.yaml" "$RHDH_NAMESPACE"
fi

# Apply latest versioned configurations
LATEST_APP_CONFIGMAP=$(find_latest_version "rhdh-app-configmap" "$CONFIG_DIR")
[ -n "$LATEST_APP_CONFIGMAP" ] && apply_resource "$LATEST_APP_CONFIGMAP" "$RHDH_NAMESPACE"

LATEST_DYNAMIC_PLUGINS=$(find_latest_version "dynamic-plugins" "$CONFIG_DIR")
[ -n "$LATEST_DYNAMIC_PLUGINS" ] && apply_resource "$LATEST_DYNAMIC_PLUGINS" "$RHDH_NAMESPACE"

LATEST_RBAC=$(find_latest_version "rbac-policy-configmap" "$CONFIG_DIR")
[ -n "$LATEST_RBAC" ] && apply_resource "$LATEST_RBAC" "$RHDH_NAMESPACE"

# Apply cluster-monitoring-config (to openshift-monitoring namespace)
if [ -f "${CONFIG_DIR}/cluster-monitoring-config-11.yaml" ]; then
    apply_resource "${CONFIG_DIR}/cluster-monitoring-config-11.yaml"
fi

# Apply Lightspeed configurations
LATEST_LS_APP=$(find_latest_version "ls-app-config-configmap" "$CONFIG_DIR")
[ -n "$LATEST_LS_APP" ] && apply_resource "$LATEST_LS_APP" "$RHDH_NAMESPACE"

LATEST_LS_STACK=$(find_latest_version "ls-stack-configmap" "$CONFIG_DIR")
[ -n "$LATEST_LS_STACK" ] && apply_resource "$LATEST_LS_STACK" "$RHDH_NAMESPACE"

# Apply non-numbered configuration files
log_info "Applying non-numbered configuration files..."

[ -f "${CONFIG_DIR}/rhdh-instance-postgresql-config.yaml" ] && \
    apply_resource "${CONFIG_DIR}/rhdh-instance-postgresql-config.yaml" "$RHDH_NAMESPACE"

[ -f "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" ] && \
    apply_resource "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" "$RHDH_NAMESPACE"

[ -f "${CONFIG_DIR}/rhdh-secrets.yaml" ] && \
    apply_resource "${CONFIG_DIR}/rhdh-secrets.yaml" "$RHDH_NAMESPACE"

# ============================================
# MCP (Model Context Protocol) Configuration
# ============================================
print_section "MCP Configuration"

EXISTING_MCP_TOKEN=$(get_secret_value "rhdh-secrets" "MCP_TOKEN" "$RHDH_NAMESPACE")

if [ -z "$EXISTING_MCP_TOKEN" ]; then
    log_info "Generating MCP_TOKEN for MCP server authentication..."

    if command -v node &>/dev/null; then
        MCP_TOKEN_RAW=$(node -p 'require("crypto").randomBytes(24).toString("base64")')
    else
        MCP_TOKEN_RAW=$(openssl rand -base64 24)
    fi

    patch_secret "rhdh-secrets" "MCP_TOKEN" "$MCP_TOKEN_RAW" "$RHDH_NAMESPACE"
    log_ok "MCP_TOKEN generated and patched into rhdh-secrets"
else
    log_skip "MCP_TOKEN already exists in rhdh-secrets"
fi

# Patch BASEDOMAIN into rhdh-secrets
log_info "Patching BASEDOMAIN into rhdh-secrets..."
patch_secret "rhdh-secrets" "BASEDOMAIN" "$BASEDOMAIN" "$RHDH_NAMESPACE"
log_ok "BASEDOMAIN patched into rhdh-secrets"

# ============================================
# TechDocs Setup (ODF, Bucket, GitLab Runner)
# ============================================
if [ "$SKIP_TECHDOCS" != "y" ]; then
    print_section "TechDocs Setup"

    # Step 1: Install ODF Operator
    if [ "$SKIP_ODF" != "y" ]; then
        log_info "Checking OpenShift Data Foundation..."

        ODF_COUNT=0
        if oc get csv -n openshift-storage &>/dev/null; then
            ODF_COUNT=$(oc get csv -n openshift-storage --no-headers 2>/dev/null | grep -c "Succeeded" || echo 0)
            ODF_COUNT=$(echo "$ODF_COUNT" | tr -d '[:space:]')
            [ -z "$ODF_COUNT" ] && ODF_COUNT=0
        fi

        if [ "$ODF_COUNT" -ge 5 ] 2>/dev/null; then
            log_skip "ODF already installed ($ODF_COUNT CSVs)"
        else
            log_info "Installing OpenShift Data Foundation operator..."
            apply_resource "../lab-prep/odf-operator.yaml"
            wait_for_odf_operator
        fi

        # Enable ODF Console Plugin (check regardless of whether ODF was just installed)
        if oc get console.operator cluster -o jsonpath='{.spec.plugins}' 2>/dev/null | grep -q "odf-console"; then
            log_skip "ODF console plugin already enabled"
        else
            log_info "Enabling ODF console plugin..."
            # Check if plugins array exists
            EXISTING_PLUGINS=$(oc get console.operator cluster -o jsonpath='{.spec.plugins}' 2>/dev/null || echo "")
            if [ -z "$EXISTING_PLUGINS" ] || [ "$EXISTING_PLUGINS" = "null" ]; then
                # Initialize plugins array with odf-console
                oc patch console.operator cluster --type json \
                    -p '[{"op": "add", "path": "/spec/plugins", "value": ["odf-console"]}]'
            else
                # Append to existing plugins array
                oc patch console.operator cluster --type json \
                    -p '[{"op": "add", "path": "/spec/plugins/-", "value": "odf-console"}]'
            fi
        fi

        # Step 2: Label worker nodes for ODF storage
        log_info "Checking worker node labels for ODF..."
        UNLABELED_NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker,!cluster.ocs.openshift.io/openshift-storage' --no-headers -o name 2>/dev/null | wc -l | tr -d '[:space:]')

        if [ "$UNLABELED_NODES" -gt 0 ] 2>/dev/null; then
            log_info "Labeling $UNLABELED_NODES worker node(s) for ODF storage..."
            oc get nodes -l 'node-role.kubernetes.io/worker' --no-headers -o name | \
                xargs -I {} oc label {} cluster.ocs.openshift.io/openshift-storage='' --overwrite
            log_ok "Worker nodes labeled for ODF"
        else
            log_skip "Worker nodes already labeled for ODF"
        fi

        # Step 3: Create Storage System/Cluster
        STORAGE_STATUS=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

        if [ "$STORAGE_STATUS" = "Ready" ]; then
            log_skip "Storage cluster already ready"
        else
            wait_for_crd "storageclusters.ocs.openshift.io"

            log_info "Creating ODF storage cluster..."
            log_info "NOTE: This may take 10-20 minutes to complete."
            apply_resource "../lab-prep/odf-storagesystem.yaml"
            wait_for_storage_cluster
        fi
    else
        log_skip "ODF installation (--skip-odf flag set)"
        ODF_READY=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$ODF_READY" != "Ready" ]; then
            log_warn "ODF is not ready. TechDocs bucket claim may fail."
        fi
    fi

    # Step 4: TechDocs bucket claim
    LATEST_TECHDOCS=$(find_latest_version "rhdh-techdocs-bucket-claim-obc" "$CONFIG_DIR")
    [ -n "$LATEST_TECHDOCS" ] && apply_resource "$LATEST_TECHDOCS" "$RHDH_NAMESPACE"

    # Step 5: GitLab Runner operator
    LATEST_RUNNER_OP=$(find_latest_version "gitlab-runner-operator" "$CONFIG_DIR")
    if [ -n "$LATEST_RUNNER_OP" ]; then
        apply_resource "$LATEST_RUNNER_OP"

        log_wait "Waiting for GitLab Runner Operator..."
        wait_for_crd "runners.apps.gitlab.com" 300
    fi

    # Step 6: GitLab Runner
    LATEST_RUNNER=$(ls -1 "${CONFIG_DIR}"/gitlab-runner-[0-9]*.yaml 2>/dev/null | \
        sed 's/.*-\([0-9]*\)\.yaml/\1 &/' | \
        sort -rn | head -1 | cut -d' ' -f2)
    [ -n "$LATEST_RUNNER" ] && apply_resource_envsubst "$LATEST_RUNNER" "gitlab-system"

    # Step 7: Configure GitLab CI/CD variables for TechDocs
    log_info "Configuring GitLab CI/CD variables for TechDocs..."
    if [ "$ssl_certs_self_signed" = "y" ]; then
        ./configure-techdocs-cicd.sh --ssl_certs_self_signed=y
    else
        ./configure-techdocs-cicd.sh
    fi
else
    log_skip "TechDocs setup (--skip-techdocs flag set)"
fi

# Dynamic plugins root PVC
LATEST_PVC=$(find_latest_version "dynamic-plugins-root-pvc" "$CONFIG_DIR")
[ -n "$LATEST_PVC" ] && apply_resource "$LATEST_PVC" "$RHDH_NAMESPACE"

# ============================================
# Lightspeed Configuration (Red Hat Demo Platform MaaS)
# ============================================
LIGHTSPEED_CONFIGURED=false
if [ "$SKIP_LIGHTSPEED" != "y" ]; then
    print_section "Lightspeed Configuration"

    if [ -n "$VLLM_URL" ] && [ -n "$VLLM_API_KEY" ] && [ -n "$VALIDATION_MODEL_NAME" ]; then
        log_info "Configuring Lightspeed with provided MaaS credentials..."

        cat <<EOF | oc apply -n "$RHDH_NAMESPACE" -f -
apiVersion: v1
kind: Secret
metadata:
  name: llama-stack-secrets
  namespace: $RHDH_NAMESPACE
type: Opaque
stringData:
  VLLM_TLS_VERIFY: ""
  VALIDATION_PROVIDER: "vllm"
  VLLM_MAX_TOKENS: ""
  VLLM_URL: "$VLLM_URL"
  VLLM_API_KEY: "$VLLM_API_KEY"
  VALIDATION_MODEL_NAME: "$VALIDATION_MODEL_NAME"
EOF

        log_ok "Lightspeed secret 'llama-stack-secrets' created!"
        LIGHTSPEED_CONFIGURED=true

        # Save to file for reference
        cat > "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: llama-stack-secrets
  namespace: $RHDH_NAMESPACE
type: Opaque
stringData:
  VLLM_TLS_VERIFY: ""
  VALIDATION_PROVIDER: "vllm"
  VLLM_MAX_TOKENS: ""
  VLLM_URL: "$VLLM_URL"
  VLLM_API_KEY: "$VLLM_API_KEY"
  VALIDATION_MODEL_NAME: "$VALIDATION_MODEL_NAME"
EOF
        log_info "File ${CONFIG_DIR}/ls-llama-stack-secrets.yaml generated."
    else
        log_info "Lightspeed credentials not provided via environment variables."
        log_info "Set VLLM_URL, VLLM_API_KEY, and VALIDATION_MODEL_NAME to configure automatically."
        echo ""
        echo "For Red Hat Demo Platform MaaS, you can get these values from:"
        echo "  https://litellm-prod-frontend.apps.maas.redhatworkshops.io/"
    fi
else
    log_skip "Lightspeed configuration (--skip-lightspeed flag set)"
fi

# Apply latest rhdh-instance (triggers restart)
LATEST_INSTANCE=$(find_latest_version "rhdh-instance" "$CONFIG_DIR")
[ -n "$LATEST_INSTANCE" ] && apply_resource "$LATEST_INSTANCE" "$RHDH_NAMESPACE"

# ============================================
# Summary
# ============================================
print_banner "Setup Complete! (Total time: $(get_elapsed_time))"

echo "GitLab:"
GITLAB_URL="https://gitlab.${BASEDOMAIN}"
echo "  URL: $GITLAB_URL"
GITLAB_PASSWORD=$(oc get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' -n "$GITLAB_NAMESPACE" 2>/dev/null | base64_decode || echo "N/A")
echo "  Admin: root / $GITLAB_PASSWORD"
echo "  User1: user1 / @abc1cde2"
echo "  User2: user2 / @abc1cde2"
echo ""

echo "Red Hat Developer Hub:"
RHDH_URL="https://$(oc get route backstage-developer-hub -n "$RHDH_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending...')"
echo "  URL: $RHDH_URL"
echo ""

echo "Applied configurations (latest versions):"
[ -n "$LATEST_APP_CONFIGMAP" ] && echo "  - $(basename "$LATEST_APP_CONFIGMAP")"
[ -n "$LATEST_DYNAMIC_PLUGINS" ] && echo "  - $(basename "$LATEST_DYNAMIC_PLUGINS")"
[ -n "$LATEST_RBAC" ] && echo "  - $(basename "$LATEST_RBAC")"
[ -n "$LATEST_LS_APP" ] && echo "  - $(basename "$LATEST_LS_APP")"
[ -n "$LATEST_LS_STACK" ] && echo "  - $(basename "$LATEST_LS_STACK")"
[ -n "$LATEST_TECHDOCS" ] && echo "  - $(basename "$LATEST_TECHDOCS")"
[ -n "$LATEST_PVC" ] && echo "  - $(basename "$LATEST_PVC")"
[ -f "${CONFIG_DIR}/rhdh-instance-postgresql-config.yaml" ] && echo "  - rhdh-instance-postgresql-config.yaml"
[ -f "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" ] && echo "  - ls-llama-stack-secrets.yaml"
[ -f "${CONFIG_DIR}/rhdh-secrets.yaml" ] && echo "  - rhdh-secrets.yaml"
[ -f "${CONFIG_DIR}/gitlab-secrets.yaml" ] && echo "  - gitlab-secrets.yaml"
[ -n "$LATEST_INSTANCE" ] && echo "  - $(basename "$LATEST_INSTANCE")"
echo ""

echo "The RHDH instance is restarting. Check status with:"
echo "  oc get pods -n $RHDH_NAMESPACE -w"
echo ""

# Lightspeed status
if [ "$LIGHTSPEED_CONFIGURED" = true ]; then
    print_banner "Lightspeed Configured!"
    echo "Lightspeed has been configured with the provided MaaS credentials."
    echo "  Model: $VALIDATION_MODEL_NAME"
    echo ""
elif [ ! -f "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" ]; then
    print_banner "REMINDER: Lightspeed Configuration Required"
    echo "To enable Red Hat Developer Lightspeed, set these environment variables"
    echo "and re-run the script (or run manually):"
    echo ""
    echo "  export VLLM_URL='https://your-maas-endpoint/v1'"
    echo "  export VLLM_API_KEY='your-api-key'"
    echo "  export VALIDATION_MODEL_NAME='meta-llama/Llama-3.3-70B-Instruct'"
    echo ""
    echo "For Red Hat Demo Platform MaaS:"
    echo "  https://maas.apps.prod.rhoai.rh-aiservices-bu.com/"
    echo ""
    echo "See README-ai-ls.md for detailed instructions."
    echo ""
fi

# MCP Server information
print_banner "MCP Server (Model Context Protocol)"
echo "MCP Server endpoint:"
echo "  ${RHDH_URL}/api/mcp-actions/v1"
echo ""
echo "To get the MCP_TOKEN for AI client configuration:"
echo "  export MCP_TOKEN=\$(oc get secret rhdh-secrets -n $RHDH_NAMESPACE -o jsonpath='{.data.MCP_TOKEN}' | base64 -d)"
echo ""
echo "See README-ai-mcp.md for integration with Continue, Cursor, or other AI clients."
echo ""

# Orchestrator sample workflow reminder
if [ "$SKIP_ORCHESTRATOR" != "y" ]; then
    print_banner "OPTIONAL: Deploy Sample Orchestrator Workflow"
    echo "To deploy a sample workflow and test the Orchestrator:"
    echo ""
    echo "  helm repo add workflows https://redhat-ads-tech.github.io/orchestrator-workflows/"
    echo "  helm install greeting-workflow workflows/greeting -n $RHDH_NAMESPACE"
    echo ""
    echo "See README-orchestrator.md for more details."
    echo ""
fi
