#!/bin/bash
# Register azuremonitor-containers extension with Arc Registration API
export HELM_EXPERIMENTAL_OCI=1

REGISTER_REGIONS_CANARY=$REGISTER_REGIONS_CANARY
RELEASE_TRAINS=$RELEASE_TRAINS
IS_CUSTOMER_HIDDEN=$IS_CUSTOMER_HIDDEN
CHART_VERSION=${CHART_VERSION}

PACKAGE_CONFIG_NAME="${PACKAGE_CONFIG_NAME:-microsoft.azuremonitor.containers-pkg022022}"
API_VERSION="${API_VERSION:-2021-05-01}"
METHOD="${METHOD:-put}"
REGISTRY_PATH_CANARY_PREVIEW="https://mcr.microsoft.com/azuremonitor/containerinsights/canary/preview/azuremonitor-containers"

if [ -z "$REGISTER_REGIONS_CANARY" ]; then
    echo "-e error release region must be provided "
    exit 1
fi
if [ -z "$RELEASE_TRAINS" ]; then
    echo "-e error release train must be provided "
    exit 1
fi
if [ -z "$IS_CUSTOMER_HIDDEN" ]; then
    echo "-e error is_customer_hidden must be provided "
    exit 1
fi
if [ -z "$CHART_VERSION" ]; then
    echo "-e error chart version must be provided "
    exit 1
fi

MCR_NAME_PATH="mcr.microsoft.com/azuremonitor/containerinsights/canary/preview/azuremonitor-containers"
echo "Pulling chart from MCR:${MCR_NAME_PATH}"
helm chart pull ${MCR_NAME_PATH}:${CHART_VERSION}
if [ $? -eq 0 ]; then
  echo "Pulling chart from MCR:${MCR_NAME_PATH}:${CHART_VERSION} completed successfully."
else
  echo "-e error Pulling chart from MCR:${MCR_NAME_PATH}:${CHART_VERSION} failed. Please review Ev2 pipeline logs for more details on the error."
  #exit 1
fi   

echo "Start arc extension release stage ${RELEASE_STAGE}, REGISTER_REGIONS is $REGISTER_REGIONS_CANARY, RELEASE_TRAINS are $RELEASE_TRAINS, PACKAGE_CONFIG_NAME is $PACKAGE_CONFIG_NAME, API_VERSION is $API_VERSION, METHOD is $METHOD"

# Create JSON request body
cat <<EOF > "request.json"
{
    "artifactEndpoints": [
        {
            "Regions": [
                $REGISTER_REGIONS_CANARY
            ],
            "Releasetrains": [
                $RELEASE_TRAINS
            ],
            "FullPathToHelmChart": "$REGISTRY_PATH_CANARY_PREVIEW",
            "ExtensionUpdateFrequencyInMinutes": 60,
            "IsCustomerHidden": $IS_CUSTOMER_HIDDEN,
            "ReadyforRollout": true,
            "RollbackVersion": null,
            "PackageConfigName": "$PACKAGE_CONFIG_NAME"
        },
EOF

sed -i '$ s/.$//' request.json

cat <<EOF >> "request.json"
    ]
}
EOF

cat request.json | jq

# Send Request
SUBSCRIPTION=${ADMIN_SUBSCRIPTION_ID}
RESOURCE_AUDIENCE=${RESOURCE_AUDIENCE}

#Login to az cli and authenticate to acr
echo "Login cli using managed identity"
az login --identity
if [ $? -eq 0 ]; then
  echo "Logged in successfully"
else
  echo "-e error az login with managed identity credentials failed. Please review the Ev2 pipeline logs for more details on the error."
  #exit 1
fi

az login --service-principal --username=${SPN_CLIENT_ID} --password=${SPN_SECRET} --tenant=${SPN_TENANT_ID}
if [ $? -eq 0 ]; then
  echo "Logged in successfully"
else
  echo "-e error failed to login to az with managed identity credentials"
  exit 1
fi    

ACCESS_TOKEN=$(az account get-access-token --resource $RESOURCE_AUDIENCE --query accessToken -o json)
if [ $? -eq 0 ]; then
  echo "get access token from resource:$RESOURCE_AUDIENCE successfully."
else
  echo "-e error get access token from resource:$RESOURCE_AUDIENCE failed. Please review Ev2 pipeline logs for more details on the error."
  exit 1
fi   
ACCESS_TOKEN=$(echo $ACCESS_TOKEN | tr -d '"' | tr -d '"\r\n')

ARC_API_URL="https://eastus2euap.dp.kubernetesconfiguration.azure.com"
EXTENSION_NAME="microsoft.azuremonitor.containers"
echo "Request parameter preparation, SUBSCRIPTION is $SUBSCRIPTION, RESOURCE_AUDIENCE is $RESOURCE_AUDIENCE, SPN_CLIENT_ID is $SPN_CLIENT_ID, SPN_TENANT_ID is $SPN_TENANT_ID, CHART_VERSION is $CHART_VERSION"

echo "start send request"
az rest --method $METHOD --headers "{\"Authorization\": \"Bearer $ACCESS_TOKEN\", \"Content-Type\": \"application/json\"}" --body @request.json --uri $ARC_API_URL/subscriptions/$SUBSCRIPTION/extensionTypeRegistrations/$EXTENSION_NAME/versions/$VERSION?api-version=$API_VERSION
if [ $? -eq 0 ]; then
  echo "arc extension registered successfully"
else
  echo "-e error failed to register arc extension"
  exit 1
fi