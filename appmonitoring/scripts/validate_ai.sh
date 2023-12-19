#!/bin/bash

# POD_DOTNET_NAME=$1
# POD_JAVA_NAME=$2
# POD_NODEJS_NAME=$3
# AI_RES_ID=$4
# NAMESPACE=$5


# Get an access token
result_rsp=$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://api.applicationinsights.io&mi_res_id=/subscriptions/66010356-d8a5-42d3-8593-6aaa3aeb1c11/resourceGroups/rambhatt-rnd-v2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/rambhatt-agentpool-es-identity' -H Metadata:true -s)
# echo "Result: $result_rsp"
access_token=$(echo $result_rsp | jq -r '.access_token')

# Define your variables
url="https://api.loganalytics.io/v1/subscriptions/66010356-d8a5-42d3-8593-6aaa3aeb1c11/resourceGroups/rambhatt-rnd-v2/providers/microsoft.insights/components/aks-final-2/query"

# Define the JSON body

json_body='{
    "query": "traces | where timestamp > ago(5m) | where cloud_RoleName == \"aks-demo-app\" | count",
    "options": {
        "truncationMaxSize": 67108864
    },
    "maxRows": 30001,
    "workspaceFilters": {
        "regions": []
    }
}'

# Make the POST request
response=$(curl -s -X POST $url \
  -H "Authorization: Bearer $access_token" \
  -H "Content-Type: application/json" \
  -d "$json_body")

# Print the response
# echo "Response: $response"

count_val=$(echo $response | jq '.tables[0].rows[0][0]')
# echo "Count: $count_val"

if (( count_val > 0 )); then
    echo $count_val
else
    echo "Not found any appropriate records" >&2
    exit 1
fi
