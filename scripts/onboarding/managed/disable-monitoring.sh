#!/bin/bash
#
# Execute this directly in Azure Cloud Shell (https://shell.azure.com) by pasting (SHIFT+INS on Windows, CTRL+V on Mac or Linux)
# the following line (beginning with curl...) at the command prompt and then replacing the args:
#  This scripts disables monitoring on to monitoring enabled managed cluster

#      1. Deletes the existing Azure Monitor for containers helm release
#      2. Deletes logAnalyticsWorkspaceResourceId tag  or disable monitoring addon (if AKS) on the provided Managed cluster
# Prerequisites :
#     Azure CLI:  https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest
#     Helm3 : https://helm.sh/docs/intro/install/
#
# bash <script> --resource-id/-r <clusterResourceId> --kube-context/-k <kube-context>
# For example to disables azure monitor for containers on monitoring enabled Azure Arc K8s cluster
# bash disable_monitoring.sh -r /subscriptions/57ac26cf-a9f0-4908-b300-9a4e9a0fb205/resourceGroups/AzureArcTest/providers/Microsoft.Kubernetes/connectedClusters/AzureArcTest1 -k MyK8sTestCluster

set -e
set -u
set -o pipefail

# default release name used during onboarding
releaseName="azmon-containers-release-1"
# resource type for azure arc clusters
resourceProvider="Microsoft.Kubernetes/connectedClusters"

# resource provider for azure arc connected cluster
arcK8sResourceProvider="Microsoft.Kubernetes/connectedClusters"
# resource provider for azure redhat openshift v4 cluster
aroV4ResourceProvider="Microsoft.RedHatOpenShift/OpenShiftClusters"
# resource provider for aks cluster
aksResourceProvider="Microsoft.ContainerService/managedClusters"

# arc k8s cluster resource
isArcK8sCluster=false

# aks cluster resource
isAksCluster=false


usage()
{
    local basename=`basename $0`
    echo
    echo "Disable Azure Monitor for containers:"
    echo "$basename --resource-id/-r <cluster resource id> --kube-context/-k <name of the kube context >"
}

delete_helm_release()
{
  echo "deleting chart release:" $releaseName
  kubeconfigContext="$(echo ${1})"
  releases=$(helm list --filter $releaseName --kube-context $kubeconfigContext)
  echo $releases
  if [[ "$releases" == *"$releaseName"* ]]; then
    helm del $releaseName --kube-context $kubeconfigContext
  else
    echo "there is no existing release of azure monitor for containers"
  fi
  echo "deletion of chart release done."
}

remove_monitoring_tags()
{
  echo "deleting monitoring tags ..."

  subscriptionId="$(echo ${1} | cut -d'/' -f3)"
  resourceGroup="$(echo ${1} | cut -d'/' -f5)"
  providerName="$(echo ${1} | cut -d'/' -f7)"
  clusterName="$(echo ${1} | cut -d'/' -f9)"

  echo "login to the azure interactively"
  az login --use-device-code

  echo "set the cluster subscription id: ${subscriptionId}"
  az account set -s ${subscriptionId}

  # validate cluster identity for ARC k8s cluster
  if [ "$isArcK8sCluster" = true ] ; then
   identitytype=$(az resource show -g ${resourceGroup} -n ${clusterName} --resource-type $resourceProvider --query identity.type)
   identitytype=$(echo $identitytype | tr "[:upper:]" "[:lower:]" | tr -d '"')
   echo "cluster identity type:" $identitytype
    if [[ "$identitytype" != "systemassigned" ]]; then
      echo "-e only supported cluster identity is systemassigned for Azure ARC K8s cluster type"
      exit 1
    fi
  fi

  echo "remove the value of loganalyticsworkspaceResourceId tag on to cluster resource"
  status=$(az resource update --set tags.logAnalyticsWorkspaceResourceId='' -g $resourceGroup -n $clusterName --resource-type $resourceProvider)

  echo "deleting of monitoring tags completed.."
}

disable_aks_monitoring_addon()
{
  echo "disabling aks monitoring addon ..."

  subscriptionId="$(echo ${1} | cut -d'/' -f3)"
  resourceGroup="$(echo ${1} | cut -d'/' -f5)"
  providerName="$(echo ${1} | cut -d'/' -f7)"
  clusterName="$(echo ${1} | cut -d'/' -f9)"

  echo "login to the azure interactively"
  az login --use-device-code

  echo "set the cluster subscription id: ${subscriptionId}"
  az account set -s ${subscriptionId}

  status=$(az aks disable-addons -a monitoring -g $resourceGroup -n $clusterName)
  echo "status after disabling addon : $status"

  echo "deleting of monitoring tags completed.."
}

parse_args()
{

 if [ $# -le 2 ]
  then
    usage
    exit 1
 fi

# Transform long options to short ones
for arg in "$@"; do
  shift
  case "$arg" in
    "--resource-id") set -- "$@" "-r" ;;
    "--kube-context") set -- "$@" "-k" ;;
    "--help")   set -- "$@" "-h" ;;
    "--"*)   usage ;;
    *)        set -- "$@" "$arg"
  esac
done

 local OPTIND opt

 while getopts 'hk:r:' opt; do
    case "$opt" in
      h)
      usage
        ;;

      k)
        kubeconfigContext="$OPTARG"
        echo "name of kube-context is $OPTARG"
        ;;

      r)
        clusterResourceId="$OPTARG"
        echo "clusterResourceId is $OPTARG"
        ;;

      ?)
        usage
        exit 1
        ;;
    esac
  done
  shift "$(($OPTIND -1))"

 subscriptionId="$(echo ${clusterResourceId} | cut -d'/' -f3)"
 resourceGroup="$(echo ${clusterResourceId} | cut -d'/' -f5)"

 # get resource parts and join back to get the provider name
 providerNameResourcePart1="$(echo ${clusterResourceId} | cut -d'/' -f7)"
 providerNameResourcePart2="$(echo ${clusterResourceId} | cut -d'/' -f8)"
 providerName="$(echo ${providerNameResourcePart1}/${providerNameResourcePart2} )"

 clusterName="$(echo ${clusterResourceId} | cut -d'/' -f9)"
 # convert to lowercase for validation
 providerName=$(echo $providerName | tr "[:upper:]" "[:lower:]")


 echo "cluster SubscriptionId:" $subscriptionId
 echo "cluster ResourceGroup:" $resourceGroup
 echo "cluster ProviderName:" $providerName
 echo "cluster Name:" $clusterName

 if [ -z "$subscriptionId" -o -z "$resourceGroup" -o -z "$providerName" -o  -z "$clusterName" ]; then
    echo "-e invalid cluster resource id. Please try with valid fully qualified resource id of the cluster"
    exit 1
 fi

 if [[ $providerName != microsoft.* ]]; then
   echo "-e invalid azure cluster resource id format."
   exit 1
 fi

 if [ -z "$kubeconfigContext" ]; then
    echo "-e kubeconfig context is empty. Please try with valid kube-context of the cluster"
    exit 1
 fi

 # detect the resource provider from the provider name in the cluster resource id
 if [ $providerName = "microsoft.kubernetes/connectedclusters" ]; then
    echo "provider cluster resource is of Azure ARC K8s cluster type"
    isArcK8sCluster=true
    resourceProvider=$arcK8sResourceProvider
 elif [ $providerName = "microsoft.redhatopenshift/openshiftclusters" ]; then
    echo "provider cluster resource is of AROv4 cluster type"
    resourceProvider=$aroV4ResourceProvider
 elif [ $providerName = "microsoft.containerservice/managedclusters" ]; then
    echo "provider cluster resource is of AKS cluster type"
    isAksCluster=true
    resourceProvider=$aksResourceProvider
 else
   echo "-e unsupported azure managed cluster type"
   exit 1
 fi

}


# parse args
parse_args $@

# delete helm release
delete_helm_release $kubeconfigContext

# remove monitoring tags on the cluster resource to make fully off boarded
if [ "$isAksCluster" = true ] ; then
   echo "disable monitoring addon since cluster is AKS"
   disable_aks_monitoring_addon $clusterResourceId
else
  remove_monitoring_tags $clusterResourceId
fi

echo "successfully disabled monitoring addon for cluster":$clusterResourceId
