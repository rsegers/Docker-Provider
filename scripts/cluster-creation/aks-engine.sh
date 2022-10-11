#!/bin/bash
set -e
TEMP_DIR=temp-$RANDOM
DEFAULT_ONPREM_K8S_CLUSTER="aks-engine-k8s-test"
AKS_ENGINE_VERSION="v0.54.0"

download-aks-engine()
{
    sudo curl -LO https://github.com/Azure/aks-engine/releases/download/${AKS_ENGINE_VERSION}/aks-engine-v0.54.0-linux-amd64.tar.gz
    sudo tar -xvf aks-engine-${AKS_ENGINE_VERSION}-linux-amd64.tar.gz
    sudo mv aks-engine-${AKS_ENGINE_VERSION}-linux-amd64 aks-engine
    sudo mv -f aks-engine/aks-engine /usr/local/bin
}


usage()
{
    local basename=`basename $0`
    echo
    echo "create aks-engine cluster:"
    echo "$basename deploy --subscription-id <subscriptionId> --client-id <clientId> --client-secret <clientSecret> --dns-prefix <dns-prefix> --location <location>"
}

parse_args()
{

 if [ $# -le 1 ]
  then
    usage
    exit 1
 fi

# Transform long options to short ones
for arg in "$@"; do
  shift
  case "$arg" in
    "--subscription-id")  set -- "$@" "-s" ;;
    "--client-id") set -- "$@" "-c" ;;
    "--client-secret") set -- "$@" "-w" ;;
    "--dns-prefix") set -- "$@" "-d" ;;
    "--location") set -- "$@" "-l" ;;
    "--"*)   usage ;;
    *)        set -- "$@" "$arg"
  esac
done

local OPTIND opt

while getopts 'hs:c:w:d:l:' opt; do
    case "$opt" in
      h)
      usage
        ;;

      s)
        subscriptionId="$OPTARG"
        echo "subscriptionId is $OPTARG"
        ;;

      c)
        clientId="$OPTARG"
        echo "clientId is $OPTARG"
        ;;

      w)
        clientSecret="$OPTARG"
        echo "clientSecret is $OPTARG"
        ;;

      d)
        dnsPrefix="$OPTARG"
        echo "dnsPrefix is $OPTARG"
        ;;

      l)
        location="$OPTARG"
        echo "location is $OPTARG"
        ;;

      ?)
        usage
        exit 1
        ;;
    esac
  done
  shift "$(($OPTIND -1))"


}
create_cluster()
{
# For docker runtime, remove kubernetesConfig block
sudo tee kubernetes.json > /dev/null << 'EOF'
{
  "apiVersion": "vlabs",
  "properties": {
    "orchestratorProfile": {
      "orchestratorType": "Kubernetes",
	   "orchestratorRelease": "1.16",
      "kubernetesConfig": {
       "containerRuntime": "containerd"
       }
    },
    "masterProfile": {
      "count": 1,
      "dnsPrefix": "",
      "vmSize": "Standard_D2_v3"
    },
    "agentPoolProfiles": [
      {
        "name": "agentpool1",
        "count": 2,
        "vmSize": "Standard_D2_v3"
      }
    ],
    "linuxProfile": {
      "adminUsername": "azureuser",
      "ssh": {
        "publicKeys": [
          {
            "keyData": ""
          }
        ]
      }
    },
    "servicePrincipalProfile": {
      "clientId": "",
      "secret": ""
    }
  }
}
EOF

echo "deploying aks-engine cluster ..."
sudo aks-engine deploy --subscription-id ${subscriptionId} --client-id ${clientId} --client-secret ${clientSecret} --dns-prefix ${dnsPrefix} --location ${location} --api-model  kubernetes.json
echo "deploying of aks-engine cluster completed."

}



echo "creating aks-engine k8s cluster ..."
echo "AKS-ENGINE version: ${AKS_ENGINE_VERSION}"
cd ~
echo "creating temp directory":$TEMP_DIR
sudo mkdir $TEMP_DIR && cd $TEMP_DIR

echo "validate args"
parse_args $@

echo "download aks-engine"
download-aks-engine

echo "creating cluster: ${ClusterName}"
create_cluster
echo "creating aks-engine cluster completed."

echo "kubeconfig of this cluster should be under ~/${TEMP_DIR}/_output/${dnsPrefix}/kubeconfig"
