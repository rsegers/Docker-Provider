#!/bin/bash

# POD_DOTNET_NAME=$1
# POD_JAVA_NAME=$2
# POD_NODEJS_NAME=$3
# AI_RES_ID=$4
# NAMESPACE=$5

# Define your variables
tenant_id="72f988bf-86f1-41af-91ab-2d7cd011db47"
client_id="02a35d9f-68ea-4a99-b688-c3a359d7cab0"
client_secret="__raw__"

# Get an access token
result_rsp=$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://api.applicationinsights.io&mi_res_id=/subscriptions/66010356-d8a5-42d3-8593-6aaa3aeb1c11/resourceGroups/rambhatt-rnd-v2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/rambhatt-agentpool-es-identity' -H Metadata:true -s)
echo "Result: $result_rsp"
access_token=$(echo $result_rsp | jq -r '.access_token')

# Use the access token
# curl 'https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Compute/virtualMachines/<vm-name>?api-version=2019-03-01' -H Metadata:true -H "Authorization: Bearer $access_token"


# Make the POST request
# response=$(curl -s -X POST https://login.microsoftonline.com/$tenant_id/oauth2/token \
#   -H "Content-Type: application/x-www-form-urlencoded" \
#   -d "grant_type=client_credentials&client_id=$client_id&resource=https://api.applicationinsights.io&client_secret=$client_secret")

# # Parse the access_token from the response
# access_token=$(echo $response | jq -r '.access_token')

# Print the access_token
echo "Access Token: $access_token"

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
echo "Response: $response"

count_val=$(echo $response | jq '.tables[0].rows[0][0]')
echo "Count: $count_val"

if (( count_val > 0 )); then
    echo $count_val
else
    echo "Not found any appropriate records" >&2
    exit 1
fi
