#!/bin/bash
# push the helm chart as an OCI artifact to specified ACR
# working directory of this script should be charts/azuremonitor-containers

export REPO_PATH="batch1/test/azure-monitor-containers"
export HELM_EXPERIMENTAL_OCI=1
export CHART_NAME="azuremonitor-containers"
export RELEASE_NAME="azmon-containers-release-1"

for ARGUMENT in "$@"
do
   KEY=$(echo $ARGUMENT | cut -f1 -d=)
   VALUE=$(echo $ARGUMENT | cut -f2 -d=)

   case "$KEY" in
           ArcK8sClusterResourceId) ArcK8sClusterResourceId=$VALUE ;;
           ArcK8sClusterRegion) ArcK8sClusterRegion=$VALUE ;;
           CIARCACR) CIARCACR=$VALUE ;;
           CICHARTVERSION) CHARTVERSION=$VALUE ;;
           KV) KV=$VALUE ;;
           KVSECRETNAMEKUBECONFIG) KVSECRETNAMEKUBECONFIG=$VALUE ;;
           CIRelease) CI_RELEASE=$VALUE ;;
           CIImageTagSuffix) CI_IMAGE_TAG_SUFFIX=$VALUE ;;
           *)
    esac
done

echo "CI ARC K8S ACR: ${CIARCACR}"
echo "CI HELM CHART VERSION: ${CHARTVERSION}"
echo "key vault name:${KV}"
echo "key vault secret name for kubeconfig:${KVSECRETNAMEKUBECONFIG}"

echo "replace linux agent image"
linuxAgentImageTag=$CI_RELEASE$CI_IMAGE_TAG_SUFFIX
echo "Linux Agent Image Tag:"$linuxAgentImageTag

imageRepo="mcr.microsoft.com/azuremonitor/containerinsights/${CI_RELEASE}"
echo "image repo: ${imageRepo}"

echo "replace windows agent image"
windowsAgentImageTag="win-"$CI_RELEASE$CI_IMAGE_TAG_SUFFIX
echo "Windows Agent Image Tag:"$windowsAgentImageTag

echo "downloading the KubeConfig from KV:${KV} and KV secret:${KVSECRETNAMEKUBECONFIG}"
az keyvault secret download --file ~/arcK8kubeconfig --vault-name ${KV} --name ${KVSECRETNAMEKUBECONFIG}
echo "downloaded the KubeConfig from KV:${KV} and KV secret:${KVSECRETNAMEKUBECONFIG}"

ACR=${CIARCACR}

echo "start: pull oci helm chart from ACR: ${ACR}"
oras pull ${ACR}/${REPO_PATH}:${CHARTVERSION} --media-type application/tar+gzip
echo "end: pull oci helm chart from ACR: ${ACR}"

echo "start: extract the chart gzip file"
rm -rf incubator
mkdir incubator
tar -xzvf ${CHART_NAME}-${CHARTVERSION}.tgz -C incubator
echo "end: extract the chart gzip file"

echo "read workspace id and key which written by get-workspace-id-and-key.sh script"
WSID=$(cat ~/WSID)
WSKEY=$(cat ~/WSKEY)

echo "Workspace GUID: ${WSID}"

echo "start: installing the chart release: ${releaseName}"
helm upgrade --install $RELEASE_NAME --kubeconfig ~/arcK8kubeconfig --set amalogs.secret.wsid=$WSID,amalogs.secret.key=$WSKEY,amalogs.env.clusterId=$ArcK8sClusterResourceId,amalogs.env.clusterRegion=$ArcK8sClusterRegion,amalogs.image.repo=$imageRepo,amalogs.image.tag=$linuxAgentImageTag,amalogs.image.tagWindows=$windowsAgentImageTag  incubator/azuremonitor-containers
echo "end: installing the chart release: ${releaseName}"
