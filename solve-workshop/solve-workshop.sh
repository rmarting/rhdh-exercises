#!/bin/bash

# Autosetup script for RHDH Workshop
# This script automates the complete setup of the workshop environment:
# 1. README-preparation.md steps (operators, GitLab, RHDH)
# 2. configure-rhdh-auth.sh (OAuth app, PAT, secrets)
# 3. Latest version of all resource YAMLs

set -e

# Running from same folder
cd $(dirname $0)

# Set default values
ssl_certs_self_signed="n"
SKIP_OPERATORS="n"
SKIP_GITLAB="n"
SKIP_RHDH_OPERATOR="n"
SKIP_ODF="n"
SKIP_TECHDOCS="n"
SKIP_ORCHESTRATOR="n"
SKIP_LIGHTSPEED="n"

# Iterate over command-line arguments
for arg in "$@"; do
    case $arg in
        --ssl_certs_self_signed=*)
            ssl_certs_self_signed="${arg#*=}"
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
            echo "  --help                     Show this help message"
            echo ""
            echo "Environment variables for Lightspeed (Red Hat Demo Platform MaaS):"
            echo "  VLLM_URL                   LLM service endpoint URL"
            echo "  VLLM_API_KEY               LLM service API key"
            echo "  VALIDATION_MODEL_NAME      Model name (e.g., meta-llama/Llama-3.3-70B-Instruct)"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check required CLI's
command -v oc >/dev/null 2>&1 || { echo >&2 "OpenShift CLI (oc) is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Aborting."; exit 1; }
command -v envsubst >/dev/null 2>&1 || { echo >&2 "envsubst is required but not installed. Aborting."; exit 1; }

# Get base domain
export BASEDOMAIN=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}' 2>/dev/null)
if [ -z "$BASEDOMAIN" ]; then
    echo "ERROR: Could not get base domain. Make sure you are logged in to OpenShift."
    exit 1
fi
echo "Base Domain: $BASEDOMAIN"

# Helper function to wait for CSV to be ready
wait_for_csv() {
    local namespace=$1
    local csv_prefix=$2
    local timeout=${3:-300}
    local elapsed=0
    
    echo "Waiting for CSV ${csv_prefix}* in namespace ${namespace} to be ready..."
    while [ $elapsed -lt $timeout ]; do
        STATUS=$(oc get csv -n "$namespace" -o jsonpath='{.items[?(@.metadata.name)].status.phase}' 2>/dev/null | grep -o "Succeeded" | head -1 || echo "")
        if [ "$STATUS" = "Succeeded" ]; then
            echo "CSV is ready!"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Still waiting... (${elapsed}s/${timeout}s)"
    done
    echo "ERROR: Timeout waiting for CSV to be ready"
    return 1
}

# Helper function to wait for GitLab to be running
wait_for_gitlab() {
    local timeout=${1:-600}
    local elapsed=0
    
    echo "Waiting for GitLab to be running..."
    while [ $elapsed -lt $timeout ]; do
        STATUS=$(oc get gitlabs gitlab -o jsonpath='{.status.phase}' -n gitlab-system 2>/dev/null || echo "")
        if [ "$STATUS" = "Running" ]; then
            echo "GitLab is running!"
            return 0
        fi
        sleep 30
        elapsed=$((elapsed + 30))
        echo "  GitLab status: ${STATUS:-pending} (${elapsed}s/${timeout}s)"
    done
    echo "ERROR: Timeout waiting for GitLab to be ready"
    return 1
}

# Helper function to wait for RHDH to be deployed
wait_for_rhdh() {
    local timeout=${1:-300}
    local elapsed=0
    
    echo "Waiting for RHDH to be deployed..."
    while [ $elapsed -lt $timeout ]; do
        STATUS=$(oc get backstage developer-hub -o jsonpath='{.status.conditions[0].type}' -n rhdh-gitlab 2>/dev/null || echo "")
        if [ "$STATUS" = "Deployed" ]; then
            echo "RHDH is deployed!"
            return 0
        fi
        sleep 15
        elapsed=$((elapsed + 15))
        echo "  RHDH status: ${STATUS:-pending} (${elapsed}s/${timeout}s)"
    done
    echo "ERROR: Timeout waiting for RHDH to be ready"
    return 1
}

# Helper function to wait for ODF operator to be ready
wait_for_odf_operator() {
    local timeout=${1:-600}
    local elapsed=0
    
    echo "Waiting for ODF operator to be ready..."
    while [ $elapsed -lt $timeout ]; do
        # Check if at least odf-operator CSV is succeeded
        ODF_STATUS=$(oc get csv -n openshift-storage -o jsonpath='{.items[?(@.metadata.name)].status.phase}' 2>/dev/null | grep -o "Succeeded" | head -1 || echo "")
        if [ "$ODF_STATUS" = "Succeeded" ]; then
            # Count how many CSVs are ready
            READY_COUNT=$(oc get csv -n openshift-storage -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Succeeded" | wc -l | tr -d '[:space:]' || echo 0)
            [ -z "$READY_COUNT" ] && READY_COUNT=0
            if [ "$READY_COUNT" -ge 5 ] 2>/dev/null; then
                echo "ODF operators are ready! ($READY_COUNT CSVs succeeded)"
                return 0
            fi
            echo "  ODF operators installing... ($READY_COUNT CSVs ready so far)"
        fi
        sleep 30
        elapsed=$((elapsed + 30))
        echo "  Still waiting... (${elapsed}s/${timeout}s)"
    done
    echo "ERROR: Timeout waiting for ODF operator to be ready"
    return 1
}

# Helper function to wait for ODF storage cluster to be ready
wait_for_storage_cluster() {
    local timeout=${1:-1200}
    local elapsed=0
    
    echo "Waiting for ODF storage cluster to be ready (this may take 10-20 minutes)..."
    while [ $elapsed -lt $timeout ]; do
        STATUS=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$STATUS" = "Ready" ]; then
            echo "Storage cluster is ready!"
            return 0
        fi
        sleep 60
        elapsed=$((elapsed + 60))
        echo "  Storage cluster status: ${STATUS:-pending} (${elapsed}s/${timeout}s)"
    done
    echo "ERROR: Timeout waiting for storage cluster to be ready"
    return 1
}

echo ""
echo "=============================================="
echo "  RHDH Workshop Auto Setup"
echo "=============================================="
echo ""

# ============================================
# Step 1: Install cert-manager operator
# ============================================
if [ "$SKIP_OPERATORS" != "y" ]; then
    echo "=== Step 1: Install cert-manager operator ==="
    
    # Check if already installed
    if oc get csv -n cert-manager-operator 2>/dev/null | grep -q "Succeeded"; then
        echo "cert-manager operator already installed, skipping..."
    else
        echo "Installing cert-manager operator..."
        oc apply -f ../lab-prep/cert-manager-operator.yaml
        wait_for_csv "cert-manager-operator" "cert-manager-operator"
    fi
    echo ""
fi

# ============================================
# Step 2: Install GitLab operator
# ============================================
if [ "$SKIP_OPERATORS" != "y" ] && [ "$SKIP_GITLAB" != "y" ]; then
    echo "=== Step 2: Install GitLab operator ==="
    
    # Check if already installed
    if oc get csv -n gitlab-system 2>/dev/null | grep -q "Succeeded"; then
        echo "GitLab operator already installed, skipping..."
    else
        echo "Installing GitLab operator..."
        oc apply -f ../lab-prep/gitlab-operator.yaml
        wait_for_csv "gitlab-system" "gitlab-operator"
    fi
    echo ""
fi

# ============================================
# Step 3: Deploy GitLab
# ============================================
if [ "$SKIP_GITLAB" != "y" ]; then
    echo "=== Step 3: Deploy GitLab ==="
    
    # Check if already deployed
    GITLAB_STATUS=$(oc get gitlabs gitlab -o jsonpath='{.status.phase}' -n gitlab-system 2>/dev/null || echo "")
    if [ "$GITLAB_STATUS" = "Running" ]; then
        echo "GitLab already running, skipping deployment..."
    else
        echo "Deploying GitLab..."
        envsubst < ../lab-prep/gitlab.yaml | oc apply -f -
        wait_for_gitlab 900  # 15 minutes timeout for GitLab
    fi
    echo ""
fi

# ============================================
# Step 4: Configure GitLab (users, groups, repos)
# ============================================
if [ "$SKIP_GITLAB" != "y" ]; then
    echo "=== Step 4: Configure GitLab ==="
    
    if [ "$ssl_certs_self_signed" = "y" ]; then
        ../lab-prep/configure-gitlab.sh --ssl_certs_self_signed=y
    else
        ../lab-prep/configure-gitlab.sh
    fi
    echo ""
fi

# ============================================
# Step 5: Install RHDH operator
# ============================================
if [ "$SKIP_OPERATORS" != "y" ] && [ "$SKIP_RHDH_OPERATOR" != "y" ]; then
    echo "=== Step 5: Install RHDH operator ==="
    
    # Check if already installed
    if oc get csv -n rhdh-operator 2>/dev/null | grep -q "Succeeded"; then
        echo "RHDH operator already installed, skipping..."
    else
        echo "Installing RHDH operator..."
        oc apply -f ../lab-prep/rhdh-operator.yaml
        wait_for_csv "rhdh-operator" "rhdh-operator"
    fi
    echo ""
fi

# ============================================
# Step 6: Install initial RHDH instance
# ============================================
echo "=== Step 6: Install initial RHDH instance ==="

# Check if already deployed
RHDH_STATUS=$(oc get backstage developer-hub -o jsonpath='{.status.conditions[0].type}' -n rhdh-gitlab 2>/dev/null || echo "")
if [ "$RHDH_STATUS" = "Deployed" ]; then
    echo "RHDH already deployed, skipping initial deployment..."
else
    echo "Deploying initial RHDH instance..."
    oc apply -f ../lab-prep/rhdh-instance.yaml
    wait_for_rhdh 300
fi
echo ""

# ============================================
# Step 7: Configure GitLab OAuth and PAT
# ============================================
echo "=== Step 7: Configure GitLab OAuth and PAT ==="

if [ "$ssl_certs_self_signed" = "y" ]; then
    ./configure-rhdh-auth.sh --ssl_certs_self_signed=y
else
    ./configure-rhdh-auth.sh
fi
echo ""

# ============================================
# Step 8: Apply latest resource configurations
# ============================================
echo "=== Step 8: Apply latest resource configurations ==="

RHDH_NAMESPACE="rhdh-gitlab"
CONFIG_DIR="../custom-app-config-gitlab"

# ============================================
# Orchestrator (OpenShift Serverless Logic)
# ============================================
if [ "$SKIP_ORCHESTRATOR" != "y" ]; then
    echo ""
    echo "=== Orchestrator Setup ==="
    
    # Check if the Serverless Logic Operator is already installed
    LOGIC_CSV_STATUS=$(oc get csv -n openshift-serverless-logic -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Succeeded" | head -1 || echo "")
    
    if [ "$LOGIC_CSV_STATUS" = "Succeeded" ]; then
        echo "OpenShift Serverless Logic Operator is already installed."
    else
        echo "Installing OpenShift Serverless Logic Operator..."
        oc apply -f ../lab-prep/logic-operator-rhel8-operator.yaml
        
        # Wait for the operator to be ready
        echo "Waiting for Serverless Logic Operator to be ready..."
        LOGIC_TIMEOUT=300
        LOGIC_ELAPSED=0
        while [ $LOGIC_ELAPSED -lt $LOGIC_TIMEOUT ]; do
            LOGIC_STATUS=$(oc get csv -n openshift-serverless-logic -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Succeeded" | head -1 || echo "")
            if [ "$LOGIC_STATUS" = "Succeeded" ]; then
                echo "Serverless Logic Operator is ready!"
                break
            fi
            sleep 10
            LOGIC_ELAPSED=$((LOGIC_ELAPSED + 10))
            echo "  Waiting for Serverless Logic Operator... (${LOGIC_ELAPSED}s/${LOGIC_TIMEOUT}s)"
        done
        
        if [ $LOGIC_ELAPSED -ge $LOGIC_TIMEOUT ]; then
            echo "WARNING: Timeout waiting for Serverless Logic Operator. Orchestrator features may not work."
        fi
    fi
else
    echo ""
    echo "Skipping Orchestrator installation (--skip-orchestrator flag set)"
fi

# Function to find the latest versioned file
find_latest_version() {
    local prefix=$1
    local dir=$2
    
    # Find files matching the pattern and get the one with highest number
    ls -1 "${dir}/${prefix}"-*.yaml 2>/dev/null | \
        sed 's/.*-\([0-9]*\)\.yaml/\1 &/' | \
        sort -rn | \
        head -1 | \
        cut -d' ' -f2
}

# Apply rhdh-secrets (generated by configure-rhdh-auth.sh)
if [ -f "${CONFIG_DIR}/gitlab-secrets.yaml" ]; then
    echo "Applying gitlab-secrets..."
    oc apply -f "${CONFIG_DIR}/gitlab-secrets.yaml" -n $RHDH_NAMESPACE
fi

# Apply latest rhdh-app-configmap
LATEST_APP_CONFIGMAP=$(find_latest_version "rhdh-app-configmap" "$CONFIG_DIR")
if [ -n "$LATEST_APP_CONFIGMAP" ]; then
    echo "Applying $(basename $LATEST_APP_CONFIGMAP)..."
    oc apply -f "$LATEST_APP_CONFIGMAP" -n $RHDH_NAMESPACE
fi

# Apply latest dynamic-plugins
LATEST_DYNAMIC_PLUGINS=$(find_latest_version "dynamic-plugins" "$CONFIG_DIR")
if [ -n "$LATEST_DYNAMIC_PLUGINS" ]; then
    echo "Applying $(basename $LATEST_DYNAMIC_PLUGINS)..."
    oc apply -f "$LATEST_DYNAMIC_PLUGINS" -n $RHDH_NAMESPACE
fi

# Apply latest rbac-policy-configmap
LATEST_RBAC=$(find_latest_version "rbac-policy-configmap" "$CONFIG_DIR")
if [ -n "$LATEST_RBAC" ]; then
    echo "Applying $(basename $LATEST_RBAC)..."
    oc apply -f "$LATEST_RBAC" -n $RHDH_NAMESPACE
fi

# Apply cluster-monitoring-config (to openshift-monitoring namespace)
if [ -f "${CONFIG_DIR}/cluster-monitoring-config-11.yaml" ]; then
    echo "Applying cluster-monitoring-config-11.yaml..."
    oc apply -f "${CONFIG_DIR}/cluster-monitoring-config-11.yaml"
fi

# Apply latest ls-app-config-configmap (Lightspeed)
LATEST_LS_APP=$(find_latest_version "ls-app-config-configmap" "$CONFIG_DIR")
if [ -n "$LATEST_LS_APP" ]; then
    echo "Applying $(basename $LATEST_LS_APP)..."
    oc apply -f "$LATEST_LS_APP" -n $RHDH_NAMESPACE
fi

# Apply latest ls-stack-configmap (Lightspeed)
LATEST_LS_STACK=$(find_latest_version "ls-stack-configmap" "$CONFIG_DIR")
if [ -n "$LATEST_LS_STACK" ]; then
    echo "Applying $(basename $LATEST_LS_STACK)..."
    oc apply -f "$LATEST_LS_STACK" -n $RHDH_NAMESPACE
fi

# Apply non-numbered configuration files
echo ""
echo "Applying non-numbered configuration files..."

# RHDH instance PostgreSQL config
if [ -f "${CONFIG_DIR}/rhdh-instance-postgresql-config.yaml" ]; then
    echo "Applying rhdh-instance-postgresql-config.yaml..."
    oc apply -f "${CONFIG_DIR}/rhdh-instance-postgresql-config.yaml" -n $RHDH_NAMESPACE
fi

# Lightspeed llama-stack secrets (if exists)
if [ -f "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" ]; then
    echo "Applying ls-llama-stack-secrets.yaml..."
    oc apply -f "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" -n $RHDH_NAMESPACE
fi

# RHDH secrets (if not already applied by configure-rhdh-auth.sh)
if [ -f "${CONFIG_DIR}/rhdh-secrets.yaml" ]; then
    echo "Applying rhdh-secrets.yaml..."
    oc apply -f "${CONFIG_DIR}/rhdh-secrets.yaml" -n $RHDH_NAMESPACE
fi

# ============================================
# MCP (Model Context Protocol) Configuration
# ============================================
echo ""
echo "=== MCP Configuration ==="

# Check if MCP_TOKEN already exists in the secret
EXISTING_MCP_TOKEN=$(oc get secret rhdh-secrets -n $RHDH_NAMESPACE -o jsonpath='{.data.MCP_TOKEN}' 2>/dev/null || echo "")

if [ -z "$EXISTING_MCP_TOKEN" ]; then
    echo "Generating MCP_TOKEN for MCP server authentication..."
    
    # Generate MCP_TOKEN using node crypto (as per README-ai-mcp.md)
    # The token is already base64 encoded for patching
    if command -v node &>/dev/null; then
        MCP_TOKEN=$(node -p 'require("crypto").randomBytes(24).toString("base64")' | base64 -w0 2>/dev/null || node -p 'require("crypto").randomBytes(24).toString("base64")' | base64)
    else
        # Fallback if node is not available
        MCP_TOKEN=$(openssl rand -base64 24 | base64 -w0 2>/dev/null || openssl rand -base64 24 | base64)
    fi
    
    # Patch rhdh-secrets with MCP_TOKEN
    oc patch secret rhdh-secrets -n $RHDH_NAMESPACE -p '{"data":{"MCP_TOKEN":"'"${MCP_TOKEN}"'"}}'
    echo "MCP_TOKEN generated and patched into rhdh-secrets"
else
    echo "MCP_TOKEN already exists in rhdh-secrets, skipping generation"
fi

# Patch BASEDOMAIN into rhdh-secrets (needed for GitLab integration URLs)
echo "Patching BASEDOMAIN into rhdh-secrets..."
BASEDOMAIN_B64=$(echo -n "$BASEDOMAIN" | base64 -w0 2>/dev/null || echo -n "$BASEDOMAIN" | base64)
oc patch secret rhdh-secrets -n $RHDH_NAMESPACE -p '{"data":{"BASEDOMAIN":"'"${BASEDOMAIN_B64}"'"}}'
echo "BASEDOMAIN patched into rhdh-secrets"

# ============================================
# TechDocs Setup (ODF, Bucket, GitLab Runner)
# ============================================
if [ "$SKIP_TECHDOCS" != "y" ]; then
    echo ""
    echo "=== TechDocs Setup ==="
    
    # Step 1: Install ODF Operator
    if [ "$SKIP_ODF" != "y" ]; then
        echo ""
        echo "Checking OpenShift Data Foundation..."
        
        # Check if ODF is already installed - simple count approach
        ODF_COUNT=0
        if oc get csv -n openshift-storage &>/dev/null; then
            ODF_COUNT=$(oc get csv -n openshift-storage --no-headers 2>/dev/null | grep -c "Succeeded" || echo 0)
            # Remove any whitespace
            ODF_COUNT=$(echo "$ODF_COUNT" | tr -d '[:space:]')
            # Default to 0 if empty
            [ -z "$ODF_COUNT" ] && ODF_COUNT=0
        fi
        
        if [ "$ODF_COUNT" -ge 5 ] 2>/dev/null; then
            echo "ODF is already installed ($ODF_COUNT CSVs), skipping operator installation..."
        else
            echo "Installing OpenShift Data Foundation operator..."
            oc apply -f ../lab-prep/odf-operator.yaml
            wait_for_odf_operator 900  # 15 minutes timeout
        fi
        
        # Step 2: Create Storage System/Cluster
        STORAGE_STATUS=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$STORAGE_STATUS" = "Ready" ]; then
            echo "Storage cluster is already ready, skipping creation..."
        else
            # Wait for CRDs to be available
            echo "Waiting for ODF CRDs to be available..."
            CRD_TIMEOUT=300
            CRD_ELAPSED=0
            while [ $CRD_ELAPSED -lt $CRD_TIMEOUT ]; do
                if oc get crd storageclusters.ocs.openshift.io &>/dev/null; then
                    echo "ODF CRDs are available!"
                    break
                fi
                sleep 10
                CRD_ELAPSED=$((CRD_ELAPSED + 10))
                echo "  Waiting for CRDs... (${CRD_ELAPSED}s/${CRD_TIMEOUT}s)"
            done
            
            if [ $CRD_ELAPSED -ge $CRD_TIMEOUT ]; then
                echo "WARNING: Timeout waiting for ODF CRDs. Storage cluster creation may fail."
            fi
            
            echo "Creating ODF storage cluster..."
            echo "NOTE: This may take 10-20 minutes to complete."
            oc apply -f ../lab-prep/odf-storagesystem.yaml
            wait_for_storage_cluster 1800  # 30 minutes timeout
        fi
    else
        echo "Skipping ODF installation (--skip-odf flag set)"
        # Check if ODF is available anyway
        ODF_READY=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$ODF_READY" != "Ready" ]; then
            echo "WARNING: ODF is not ready. TechDocs bucket claim may fail."
        fi
    fi
    
    # Step 3: TechDocs bucket claim (latest version)
    LATEST_TECHDOCS=$(find_latest_version "rhdh-techdocs-bucket-claim-obc" "$CONFIG_DIR")
    if [ -n "$LATEST_TECHDOCS" ]; then
        echo "Applying $(basename $LATEST_TECHDOCS)..."
        oc apply -f "$LATEST_TECHDOCS" -n $RHDH_NAMESPACE
    fi
    
    # Step 4: GitLab Runner operator (latest version)
    LATEST_RUNNER_OP=$(find_latest_version "gitlab-runner-operator" "$CONFIG_DIR")
    if [ -n "$LATEST_RUNNER_OP" ]; then
        echo "Applying $(basename $LATEST_RUNNER_OP)..."
        oc apply -f "$LATEST_RUNNER_OP"
        
        # Wait for GitLab Runner Operator to be ready
        echo "Waiting for GitLab Runner Operator to be ready..."
        RUNNER_OP_TIMEOUT=300
        RUNNER_OP_ELAPSED=0
        while [ $RUNNER_OP_ELAPSED -lt $RUNNER_OP_TIMEOUT ]; do
            RUNNER_OP_STATUS=$(oc get csv -n gitlab-system -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Succeeded" | head -1 || echo "")
            if [ "$RUNNER_OP_STATUS" = "Succeeded" ]; then
                # Also check if Runner CRD is available
                if oc get crd runners.apps.gitlab.com &>/dev/null; then
                    echo "GitLab Runner Operator is ready!"
                    break
                fi
            fi
            sleep 10
            RUNNER_OP_ELAPSED=$((RUNNER_OP_ELAPSED + 10))
            echo "  Waiting for GitLab Runner Operator... (${RUNNER_OP_ELAPSED}s/${RUNNER_OP_TIMEOUT}s)"
        done
        
        if [ $RUNNER_OP_ELAPSED -ge $RUNNER_OP_TIMEOUT ]; then
            echo "WARNING: Timeout waiting for GitLab Runner Operator. Runner creation may fail."
        fi
    fi
    
    # Step 5: GitLab Runner (latest version)
    # Exclude gitlab-runner-operator files
    LATEST_RUNNER=$(ls -1 "${CONFIG_DIR}"/gitlab-runner-[0-9]*.yaml 2>/dev/null | \
        sed 's/.*-\([0-9]*\)\.yaml/\1 &/' | \
        sort -rn | head -1 | cut -d' ' -f2)
    if [ -n "$LATEST_RUNNER" ]; then
        echo "Applying $(basename $LATEST_RUNNER)..."
        envsubst < "$LATEST_RUNNER" | oc apply -n gitlab-system -f -
    fi
    
    # Step 6: Configure GitLab CI/CD variables for TechDocs
    echo ""
    echo "Configuring GitLab CI/CD variables for TechDocs..."
    if [ "$ssl_certs_self_signed" = "y" ]; then
        ./configure-techdocs-cicd.sh --ssl_certs_self_signed=y
    else
        ./configure-techdocs-cicd.sh
    fi
else
    echo ""
    echo "Skipping TechDocs setup (--skip-techdocs flag set)"
fi

# Dynamic plugins root PVC (latest version)
LATEST_PVC=$(find_latest_version "dynamic-plugins-root-pvc" "$CONFIG_DIR")
if [ -n "$LATEST_PVC" ]; then
    echo "Applying $(basename $LATEST_PVC)..."
    oc apply -f "$LATEST_PVC" -n $RHDH_NAMESPACE
fi

echo ""

# ============================================
# Lightspeed Configuration (Red Hat Demo Platform MaaS)
# ============================================
LIGHTSPEED_CONFIGURED=false
if [ "$SKIP_LIGHTSPEED" != "y" ]; then
    echo "=== Lightspeed Configuration ==="
    
    # Check if environment variables are set
    if [ -n "$VLLM_URL" ] && [ -n "$VLLM_API_KEY" ] && [ -n "$VALIDATION_MODEL_NAME" ]; then
        echo "Configuring Lightspeed with provided MaaS credentials..."
        
        # Create the llama-stack-secrets secret
        cat <<EOF | oc apply -n $RHDH_NAMESPACE -f -
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
        
        echo "Lightspeed secret 'llama-stack-secrets' created successfully!"
        LIGHTSPEED_CONFIGURED=true
        
        # Also create/update the ls-llama-stack-secrets.yaml file for reference
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
        echo "File ${CONFIG_DIR}/ls-llama-stack-secrets.yaml generated."
    else
        echo "Lightspeed credentials not provided via environment variables."
        echo "Set VLLM_URL, VLLM_API_KEY, and VALIDATION_MODEL_NAME to configure automatically."
        echo ""
        echo "For Red Hat Demo Platform MaaS, you can get these values from:"
        echo "  https://litellm-prod-frontend.apps.maas.redhatworkshops.io/"
        echo ""
    fi
else
    echo ""
    echo "Skipping Lightspeed configuration (--skip-lightspeed flag set)"
fi

echo ""

# Apply latest rhdh-instance (this will trigger a restart)
LATEST_INSTANCE=$(find_latest_version "rhdh-instance" "$CONFIG_DIR")
if [ -n "$LATEST_INSTANCE" ]; then
    echo "Applying $(basename $LATEST_INSTANCE)..."
    oc apply -f "$LATEST_INSTANCE" -n $RHDH_NAMESPACE
fi

echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "GitLab:"
GITLAB_URL="https://gitlab.${BASEDOMAIN}"
echo "  URL: $GITLAB_URL"
GITLAB_PASSWORD=$(oc get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' -n gitlab-system 2>/dev/null | base64 -d 2>/dev/null || echo "N/A")
echo "  Admin: root / $GITLAB_PASSWORD"
echo "  User1: user1 / @abc1cde2"
echo "  User2: user2 / @abc1cde2"
echo ""
echo "Red Hat Developer Hub:"
RHDH_URL="https://$(oc get route backstage-developer-hub -n rhdh-gitlab -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending...')"
echo "  URL: $RHDH_URL"
echo ""
echo "Applied configurations (latest versions):"
[ -n "$LATEST_APP_CONFIGMAP" ] && echo "  - $(basename $LATEST_APP_CONFIGMAP)"
[ -n "$LATEST_DYNAMIC_PLUGINS" ] && echo "  - $(basename $LATEST_DYNAMIC_PLUGINS)"
[ -n "$LATEST_RBAC" ] && echo "  - $(basename $LATEST_RBAC)"
[ -n "$LATEST_LS_APP" ] && echo "  - $(basename $LATEST_LS_APP)"
[ -n "$LATEST_LS_STACK" ] && echo "  - $(basename $LATEST_LS_STACK)"
[ -n "$LATEST_TECHDOCS" ] && echo "  - $(basename $LATEST_TECHDOCS)"
[ -n "$LATEST_PVC" ] && echo "  - $(basename $LATEST_PVC)"
[ -f "${CONFIG_DIR}/rhdh-instance-postgresql-config.yaml" ] && echo "  - rhdh-instance-postgresql-config.yaml"
[ -f "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" ] && echo "  - ls-llama-stack-secrets.yaml"
[ -f "${CONFIG_DIR}/rhdh-secrets.yaml" ] && echo "  - rhdh-secrets.yaml"
[ -f "${CONFIG_DIR}/gitlab-secrets.yaml" ] && echo "  - gitlab-secrets.yaml"
[ -n "$LATEST_INSTANCE" ] && echo "  - $(basename $LATEST_INSTANCE)"
echo ""
echo "The RHDH instance is restarting. Check status with:"
echo "  oc get pods -n rhdh-gitlab -w"
echo ""

# Check if Lightspeed secrets need to be configured
if [ "$LIGHTSPEED_CONFIGURED" = true ]; then
    echo "=============================================="
    echo "  Lightspeed Configured!"
    echo "=============================================="
    echo ""
    echo "Lightspeed has been configured with the provided MaaS credentials."
    echo "  Model: $VALIDATION_MODEL_NAME"
    echo ""
elif [ ! -f "${CONFIG_DIR}/ls-llama-stack-secrets.yaml" ]; then
    echo "=============================================="
    echo "  REMINDER: Lightspeed Configuration Required"
    echo "=============================================="
    echo ""
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
echo "=============================================="
echo "  MCP Server (Model Context Protocol)"
echo "=============================================="
echo ""
echo "MCP Server endpoint:"
echo "  ${RHDH_URL}/api/mcp-actions/v1"
echo ""
echo "To get the MCP_TOKEN for AI client configuration:"
echo "  export MCP_TOKEN=\$(oc get secret rhdh-secrets -n rhdh-gitlab -o jsonpath='{.data.MCP_TOKEN}' | base64 -d)"
echo ""
echo "See README-ai-mcp.md for integration with Continue, Cursor, or other AI clients."
echo ""

# Orchestrator sample workflow reminder
if [ "$SKIP_ORCHESTRATOR" != "y" ]; then
    echo "=============================================="
    echo "  OPTIONAL: Deploy Sample Orchestrator Workflow"
    echo "=============================================="
    echo ""
    echo "To deploy a sample workflow and test the Orchestrator:"
    echo ""
    echo "  helm repo add workflows https://redhat-ads-tech.github.io/orchestrator-workflows/"
    echo "  helm install greeting-workflow workflows/greeting -n rhdh-gitlab"
    echo ""
    echo "See README-orchestrator.md for more details."
    echo ""
fi
