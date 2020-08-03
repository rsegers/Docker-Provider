#!/bin/bash
# push the helm chart as an OCI artifact to specified ACR
# working directory of this script should be charts/azuremonitor-containers

export REPO_PATH="batch1/test/azure-monitor-containers"
export  HELM_EXPERIMENTAL_OCI=1

for ARGUMENT in "$@"
do
   KEY=$(echo $ARGUMENT | cut -f1 -d=)
   VALUE=$(echo $ARGUMENT | cut -f2 -d=)

   case "$KEY" in
           CIARCACR) CIARCACR=$VALUE ;;
           CICHARTVERSION) CHARTVERSION=$VALUE ;;
           *)
    esac
done

echo "CI ARC K8S ACR: ${CIARCACR}"
echo "CI HELM CHART VERSION: ${CHARTVERSION}"

echo "start: read appid and appsecret"
ACR_APP_ID=$(cat ~/acrappid)
ACR_APP_SECRET=$(cat ~/acrappsecret)
echo "end: read appid and appsecret"

ACR=${CIARCACR}

echo "login to acr:${ACR} using oras"
oras login $ACR  --username $ACR_APP_ID --password $ACR_APP_SECRET
echo "login to acr:${ACR} completed: ${ACR}"

echo "start: push the chart version: ${CHARTVERSION} to acr repo: ${ACR}"

echo "generate helm package"
helm package .

echo "pushing the helm chart as an OCI artifact"
oras push ${ACR}/${REPO_PATH}:${CHARTVERSION} --manifest-config /dev/null:application/vnd.unknown.config.v1+json  ./azuremonitor-containers-${CHARTVERSION}.tgz:application/tar+gzip

echo "end: push the chart version: ${CHARTVERSION} to acr repo: ${ACR}"
