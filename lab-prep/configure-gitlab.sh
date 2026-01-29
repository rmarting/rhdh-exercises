#!/bin/bash

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
    # Declare local variables
    echo "SSL Certificates self signed enabled."
    CURL_DISABLE_SSL_VERIFICATION="-k"
    GIT_DISABLE_SSL_VERIFICATION="-c http.sslVerify=false"
fi

# Check required CLI's
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed.  Aborting."; exit 1; }
command -v oc >/dev/null 2>&1 || { echo >&2 "OpenShift CLI is required but not installed.  Aborting."; exit 1; }

#GitLab token must be 20 characters
DEFAULT_GITLAB_TOKEN="KbfdXFhoX407c0v5ZP2Y"

GITLAB_TOKEN=${GITLAB_TOKEN:=$DEFAULT_GITLAB_TOKEN}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:=gitlab-system}

GITLAB_URL=https://$(oc get ingress -n $GITLAB_NAMESPACE -l app=webservice -o jsonpath='{ .items[*].spec.rules[*].host }')

# Check if Token has been registered
if [ "401" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s -I "${GITLAB_URL}/api/v4/user" -w "%{http_code}" -o /dev/null) ]; then
    echo "Registering Token"
    # Create root token
    oc exec -it -n $GITLAB_NAMESPACE -c toolbox $(oc get pods -n $GITLAB_NAMESPACE -l=app=toolbox -o jsonpath='{ .items[0].metadata.name }') -- sh -c "$(cat << EOF
    gitlab-rails runner "User.find_by_username('root').personal_access_tokens.create(scopes: [:api], name: 'Automation token', expires_at: 365.days.from_now, token_digest: Gitlab::CryptoHelper.sha256('${GITLAB_TOKEN}'))"
EOF
    )"
fi

# Create Groups
if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-a" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"path": "team-a", "name": "team-a", "visibility": "public" }' \
    "${GITLAB_URL}/api/v4/groups" &> /dev/null
fi

if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-b" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"path": "team-b", "name": "team-b", "visibility": "public" }' \
    "${GITLAB_URL}/api/v4/groups" &> /dev/null
fi

if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=rhdh" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"path": "rhdh", "name": "rhdh", "visibility": "public" }' \
    "${GITLAB_URL}/api/v4/groups" &> /dev/null
fi

TEAM_A_ID=$(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-a" | jq -r '(.|first).id')
TEAM_B_ID=$(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-b" | jq -r '(.|first).id')

# Create Users
if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=user1" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data '{"email": "user1@redhat.com", "password": "@abc1cde2","name": "user1","username": "user1", "skip_confirmation": "true" }' \
        "${GITLAB_URL}/api/v4/users" &> /dev/null
fi

if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=user2" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data '{"email": "user2@redhat.com", "password": "@abc1cde2","name": "user2","username": "user2", "skip_confirmation": "true" }' \
        "${GITLAB_URL}/api/v4/users" &> /dev/null
fi

USER1_ID=$(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=user1" | jq -r '(.|first).id')
USER2_ID=$(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=user2" | jq -r '(.|first).id')

# Add users to groups
if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups/$TEAM_A_ID/members?user_ids=$USER1_ID" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"user_id\": \"$USER1_ID\", \"access_level\": 50 }" \
        "${GITLAB_URL}/api/v4/groups/$TEAM_A_ID/members" &> /dev/null
fi

if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups/$TEAM_B_ID/members?user_ids=$USER2_ID" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"user_id\": \"$USER2_ID\", \"access_level\": 50 }" \
        "${GITLAB_URL}/api/v4/groups/$TEAM_B_ID/members" &> /dev/null
fi

# Create Projects
if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/projects?search=sample-app" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"namespace_id\": \"$TEAM_A_ID\", \"name\": \"sample-app\", \"visibility\": \"public\" }" \
        "${GITLAB_URL}/api/v4/projects" &> /dev/null
fi

# Add some content to the repo
# Check if content already exists in the repo
REPO_FILES=$(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/projects/team-a%2Fsample-app/repository/tree" | jq length 2>/dev/null || echo "0")

if [ "$REPO_FILES" = "0" ] || [ "$REPO_FILES" = "null" ]; then
    echo "Adding initial content to sample-app repository..."
    
    # Clean up any existing temp directory
    rm -rf /tmp/sample-app
    
    # Clone the repo
    git $GIT_DISABLE_SSL_VERIFICATION clone ${GITLAB_URL}/team-a/sample-app.git /tmp/sample-app
    
    # Copy files
    cp catalog-info.yaml users-groups.yaml systems.yaml /tmp/sample-app/
    
    # Commit
    git $GIT_DISABLE_SSL_VERIFICATION -C /tmp/sample-app/ add .
    git $GIT_DISABLE_SSL_VERIFICATION -C /tmp/sample-app commit -m "initial commit" --author="user1 <user1@redhat.com>"
    
    # Push using token-based URL (no interactive password prompt)
    GITLAB_HOST=$(echo $GITLAB_URL | sed 's|https://||')
    git $GIT_DISABLE_SSL_VERIFICATION -C /tmp/sample-app remote set-url origin "https://root:${GITLAB_TOKEN}@${GITLAB_HOST}/team-a/sample-app.git"
    git $GIT_DISABLE_SSL_VERIFICATION -C /tmp/sample-app push
    
    # Clean up
    rm -rf /tmp/sample-app
    echo "Repository initialized successfully!"
else
    echo "Repository already has content, skipping initialization..."
fi
