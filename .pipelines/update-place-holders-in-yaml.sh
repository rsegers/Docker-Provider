#!/bin/bash

echo "start: update placeholders such as clusterResourceId, clusterRegion, WSID, WSKEY and Image etc.."

for ARGUMENT in "$@"
do
   KEY=$(echo $ARGUMENT | cut -f1 -d=)
   VALUE=$(echo $ARGUMENT | cut -f2 -d=)

   case "$KEY" in
           ClusterResourceId) ClusterResourceId=$VALUE ;;
           ClusterRegion) ClusterRegion=$VALUE ;;
           UserAssignedIdentityClientId) UserAssignedIdentityClientId=$VALUE ;;
           CIRelease) CI_RELEASE=$VALUE ;;
           CIImageTagSuffix) CI_IMAGE_TAG_SUFFIX=$VALUE ;;
           *)
    esac
done

echo "clusterResourceId:$ClusterResourceId"
echo "replace cluster resource id"
sed -i "s=VALUE_AKS_RESOURCE_ID_VALUE=$ClusterResourceId=g" ama-logs.yaml

echo "clusterRegion:$ClusterRegion"
echo "replace cluster region"
sed -i "s/VALUE_AKS_RESOURCE_REGION_VALUE/$ClusterRegion/g" ama-logs.yaml

echo "userAssignedIdentityClientId:$UserAssignedIdentityClientId"
echo "replace user assigned identity client id"
sed -i "s=VALUE_USER_ASSIGNED_IDENTITY_CLIENT_ID_VALUE=$UserAssignedIdentityClientId=g" ama-logs.yaml

echo "replace linux agent image"
linuxAgentImageTag=$CI_RELEASE$CI_IMAGE_TAG_SUFFIX
echo "Linux Agent Image Tag:"$linuxAgentImageTag

linuxAgentImage="mcr.microsoft.com/azuremonitor/containerinsights/${CI_RELEASE}:${linuxAgentImageTag}"
imagePrefixLinuxAgent="mcr.microsoft.com/azuremonitor/containerinsights/ciprod:ciprod[0-9]*(-[0-9])?"
sed -i -E "s=$imagePrefixLinuxAgent=$linuxAgentImage=g" ama-logs.yaml

echo "replace windows agent image"
windowsAgentImageTag="win-"$CI_RELEASE$CI_IMAGE_TAG_SUFFIX
echo "Windows Agent Image Tag:"$windowsAgentImageTag

windowsAgentImage="mcr.microsoft.com/azuremonitor/containerinsights/${CI_RELEASE}:${windowsAgentImageTag}"
imagePrefixWindowsAgent="mcr.microsoft.com/azuremonitor/containerinsights/ciprod:win-ciprod[0-9]*(-[0-9])?"
sed -i -E "s=$imagePrefixWindowsAgent=$windowsAgentImage=g" ama-logs.yaml


echo "read workspace id and key which written by get-workspace-id-and-key.sh script"
WSID=$(cat ~/WSID)
WSKEY=$(cat ~/WSKEY)

echo "log analytics workspace guid: ${WSID}"
# avoid wskey in the logs and uncomment if required for debugging
# echo "log analytics workspace key: ${WSKEY}"

echo "Base64 encoding WSID and WSKEY values"
Base64EncodedWSID=$(echo $WSID | base64 | tr -d '\n' | tr -d '\r')
Base64EncodedWSKEY=$(echo $WSKEY | base64 | tr -d '\n' | tr -d '\r')

echo "Base64 encoded log analytics workspace guid: ${Base64EncodedWSID}"
# avoid wskey in the logs and uncomment if required for debugging
# echo "Base64 encoded log analytics workspace key: ${Base64EncodedWSKEY}"

echo "replace base64 encoded log analytics workspace id"
sed -i "s/VALUE_WSID/$Base64EncodedWSID/g" ama-logs.yaml

echo "replace base64 encoded log analytics workspace key"
sed -i "s/VALUE_KEY/$Base64EncodedWSKEY/g" ama-logs.yaml

echo "end: update placeholders such as clusterResourceId, clusterRegion, WSID, WSKEY and Image etc.."
