#!/bin/bash

echo "start: pull linux agent image from cdpx and push to ciprod acr"

for ARGUMENT in "$@"
do
   KEY=$(echo $ARGUMENT | cut -f1 -d=)
   VALUE=$(echo $ARGUMENT | cut -f2 -d=)

   case "$KEY" in
           CDPXACRLinux) CDPX_ACR=$VALUE ;;
           CDPXLinuxAgentRepositoryName) CDPX_REPO_NAME=$VALUE ;;
           CDPXLinuxAgentImageTag) CDPX_AGENT_IMAGE_TAG=$VALUE ;;
           CIACR) CI_ACR=$VALUE ;;
           CIAgentRepositoryName) CI_AGENT_REPO=$VALUE ;;
           CIRelease) CI_RELEASE=$VALUE ;;
           CIImageTagSuffix) CI_IMAGE_TAG_SUFFIX=$VALUE ;;

           *)
    esac
done

echo "start: read appid and appsecret"
ACR_APP_ID=$(cat ~/acrappid)
ACR_APP_SECRET=$(cat ~/acrappsecret)
echo "end: read appid and appsecret"

echo "start: read appid and appsecret for cdpx"
CDPX_ACR_APP_ID=$(cat ~/cdpxacrappid)
CDPX_ACR_APP_SECRET=$(cat ~/cdpxacrappsecret)
echo "end: read appid and appsecret which has read access on cdpx acr"


# Name of CDPX_ACR should be in this format :Naming convention: 'cdpx' + service tree id without '-' + two digit suffix like'00'/'01
# suffix 00 primary and 01 secondary, and we only use primary
# This configured via pipeline variable
echo "login to cdpxlinux acr:${CDPX_ACR}"
docker login $CDPX_ACR  --username $CDPX_ACR_APP_ID --password $CDPX_ACR_APP_SECRET
echo "login to cdpxlinux acr completed: ${CDPX_ACR}"

echo "pull agent image from cdpxlinux acr: ${CDPX_ACR}"
docker pull ${CDPX_ACR}/official/${CDPX_REPO_NAME}:${CDPX_AGENT_IMAGE_TAG}
echo "pull image from cdpxlinux acr completed: ${CDPX_ACR}"

echo "CI Release name is:"$CI_RELEASE
imagetag=$CI_RELEASE$CI_IMAGE_TAG_SUFFIX
echo "agentimagetag="$imagetag

echo "CI ACR : ${CI_ACR}"
echo "CI AGENT REPOSITORY NAME : ${CI_AGENT_REPO}"

echo "tag linux agent image"
docker tag ${CDPX_ACR}/official/${CDPX_REPO_NAME}:${CDPX_AGENT_IMAGE_TAG} ${CI_ACR}/public/azuremonitor/containerinsights/${CI_AGENT_REPO}:${imagetag}

echo "login ciprod acr":$CI_ACR
docker login $CI_ACR --username $ACR_APP_ID --password $ACR_APP_SECRET
echo "login to ${CI_ACR} acr completed"

echo "pushing the image to ciprod acr:${CI_ACR}"
docker push ${CI_ACR}/public/azuremonitor/containerinsights/${CI_AGENT_REPO}:${imagetag}
echo "pushing the image to ciprod acr completed"

echo "end: pull linux agent image from cdpx and push to ciprod acr"
