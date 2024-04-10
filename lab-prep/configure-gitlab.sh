#!/bin/bash

# Check required CLI's
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed.  Aborting."; exit 1; } 
command -v oc >/dev/null 2>&1 || { echo >&2 "OpenShift CLI is required but not installed.  Aborting."; exit 1; }

#GitLab token must be 20 characters
DEFAULT_GITLAB_TOKEN="KbfdXFhoX407c0v5ZP2Y"

GITLAB_TOKEN=${GITLAB_TOKEN:=$DEFAULT_GITLAB_TOKEN}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:=gitlab-system}

GITLAB_URL=https://$(oc get ingress -n $GITLAB_NAMESPACE -l app=webservice -o jsonpath='{ .items[*].spec.rules[*].host }')

# Check if Token has been registered
if [ "401" == $(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s -I "${GITLAB_URL}/api/v4/user" -w "%{http_code}" -o /dev/null) ]; then
    echo "Registering Token"
    # Create root token
    oc exec -it -n $GITLAB_NAMESPACE -c toolbox $(oc get pods -n $GITLAB_NAMESPACE -l=app=toolbox -o jsonpath='{ .items[0].metadata.name }') -- sh -c "$(cat << EOF
    gitlab-rails runner "User.find_by_username('root').personal_access_tokens.create(scopes: [:api], name: 'Automation token', expires_at: 365.days.from_now, token_digest: Gitlab::CryptoHelper.sha256('${GITLAB_TOKEN}'))"
    EOF
    )"
fi

# Create Groups
if [ "0" == $(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-a" | jq length) ]; then
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"path": "team-a", "name": "team-a" }' \
    "${GITLAB_URL}/api/v4/groups" &> /dev/null
fi

if [ "0" == $(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-b" | jq length) ]; then
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"path": "team-b", "name": "team-b" }' \
    "${GITLAB_URL}/api/v4/groups" &> /dev/null
fi

TEAM_A_ID=$(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-a" | jq -r '(.|first).id')
TEAM_B_ID=$(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-b" | jq -r '(.|first).id')

# Create Users
if [ "0" == $(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=user1" | jq length) ]; then
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data '{"email": "user1@redhat.com", "password": "@abc1cde2","name": "user1","username": "user1" }' \
        "${GITLAB_URL}/api/v4/users" &> /dev/null
fi

if [ "0" == $(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=user2" | jq length) ]; then
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data '{"email": "user2@redhat.com", "password": "@abc1cde2","name": "user2","username": "user2" }' \
        "${GITLAB_URL}/api/v4/users" &> /dev/null
fi

USER1_ID=$(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=user1" | jq -r '(.|first).id')
USER2_ID=$(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=user2" | jq -r '(.|first).id')

# Add users to groups
if [ "0" == $(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups/$TEAM_A_ID/members?user_ids=$USER1_ID" | jq length) ]; then
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"user_id\": \"$USER1_ID\", \"access_level\": 50 }" \
        "${GITLAB_URL}/api/v4/groups/$TEAM_A_ID/members" &> /dev/null
fi

if [ "0" == $(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups/$TEAM_B_ID/members?user_ids=$USER2_ID" | jq length) ]; then
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"user_id\": \"$USER2_ID\", \"access_level\": 50 }" \
        "${GITLAB_URL}/api/v4/groups/$TEAM_B_ID/members" &> /dev/null
fi

# Create Projects
if [ "0" == $(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/projects?search=sample-app" | jq length) ]; then
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"namespace_id\": \"$TEAM_A_ID\", \"name\": \"sample-app\" }" \
        "${GITLAB_URL}/api/v4/projects" &> /dev/null
fi