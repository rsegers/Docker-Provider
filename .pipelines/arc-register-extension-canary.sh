#!/bin/bash
# Register azuremonitor-containers extension with Arc Registration API

REGION_STAGING=${REGION_STAGING:-'"eastus2euap"'}
RELEASE_TRAIN_STAGING=${RELEASE_TRAIN:-preview}

PACKAGE_CONFIG_NAME="${PACKAGE_CONFIG_NAME:-microsoft.azuremonitor.containers-pkg022022}"
API_VERSION="${API_VERSION:-2021-05-01}"
METHOD="${METHOD:-put}"
REGISTRY_STAGING="https://mcr.microsoft.com/azuremonitor/containerinsights/canary/preview/azuremonitor-containers"

echo "Start arc extension registration, REGION_STAGING is ${REGION_STAGING}, RELEASE_TRAIN_STAGING is ${RELEASE_TRAIN_STAGING}, PACKAGE_CONFIG_NAME is ${PACKAGE_CONFIG_NAME}, API_VERSION is ${API_VERSION}, METHOD is ${METHOD}"

# Create JSON request body
cat <<EOF > "request.json"
{
    "artifactEndpoints": [
        {
            "Regions": [
                $REGION_STAGING
            ],
            "Releasetrains": [
                "$RELEASE_TRAIN_STAGING"
            ],
            "FullPathToHelmChart": "$REGISTRY_STAGING",
            "ExtensionUpdateFrequencyInMinutes": 60,
            "IsCustomerHidden": false,
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
RESOURCE_ID=${RESOURCE_ID}
az login --service-principal --username=${SPN_CLIENT_ID} --password=${SPN_SECRET} --tenant=${SPN_TENANT_ID}

ACCESS_TOKEN=$(az account get-access-token --resource $RESOURCE_ID --query accessToken -o json)
ACCESS_TOKEN=$(echo $ACCESS_TOKEN | tr -d '"' | tr -d '"\r\n')
ARC_API_URL="https://eastus2euap.dp.kubernetesconfiguration.azure.com"
VERSION=${VERSION}
EXTENSION_NAME="microsoft.azuremonitor.containers"

az rest --method $METHOD --headers "{\"Authorization\": \"Bearer $ACCESS_TOKEN\", \"Content-Type\": \"application/json\"}" --body @request.json --uri $ARC_API_URL/subscriptions/$SUBSCRIPTION/extensionTypeRegistrations/$EXTENSION_NAME/versions/$VERSION?api-version=$API_VERSION

