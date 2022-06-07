#!/bin/bash

echo "start: install azure-monitor for containers chart to specificied aks-engine cluster"
releaseName="azmon-containers-release-1"

for ARGUMENT in "$@"
do
   KEY=$(echo $ARGUMENT | cut -f1 -d=)
   VALUE=$(echo $ARGUMENT | cut -f2 -d=)

   case "$KEY" in
           ClusterName) ClusterName=$VALUE ;;
           CIRelease) CI_RELEASE=$VALUE ;;
           CIImageTagSuffix) CI_IMAGE_TAG_SUFFIX=$VALUE ;;
           *)
    esac
done


echo "replace linux agent image"
linuxAgentImageTag=$CI_RELEASE$CI_IMAGE_TAG_SUFFIX
echo "Linux Agent Image Tag:"$linuxAgentImageTag

imageRepo="mcr.microsoft.com/azuremonitor/containerinsights/${CI_RELEASE}"
echo "image repo: ${imageRepo}"

echo "replace windows agent image"
windowsAgentImageTag="win-"$CI_RELEASE$CI_IMAGE_TAG_SUFFIX
echo "Windows Agent Image Tag:"$windowsAgentImageTag

echo "read workspace id and key which written by get-workspace-id-and-key.sh script"
WSID=$(cat ~/WSID)
WSKEY=$(cat ~/WSKEY)

echo "Workspace GUID: ${WSID}"
# dont log key and enable for debugging
# echo "Workspace Key: ${WSKEY}"

# kubeconfig=$(cat ~/kubeconfig)
# echo "kubeconfig:${kubeconfig}"

echo "installing the chart release: ${releaseName}"
helm upgrade --install $releaseName --kubeconfig ~/kubeconfig --set ama-logs.secret.wsid=$WSID,ama-logs.secret.key=$WSKEY,ama-logs.env.clusterName=$ClusterName,ama-logs.image.repo=$imageRepo,ama-logs.image.tag=$linuxAgentImageTag,ama-logs.image.tagWindows=$windowsAgentImageTag  azuremonitor-containers
