# Instructions to create k8s clusters

## On-Prem K8s Cluster

on-prem k8s cluster can be created on any VM or physical machine using kind.

```
bash onprem-k8s.sh --cluster-name <name-of-the-cluster>
```

## AKS-Engine cluster

aks-engine is unmanaged cluster in azure and you can use below command to create the cluster in azure.

```

# Either you can reuse existing service principal or create one with below instructions
subscriptionId="<subscription id>"
az account set -s ${subscriptionId}
sp=$(az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/${subscriptionId}")
# get the appId (i.e. clientid) and password (i.e. clientSecret)
echo $sp

clientId=$(echo $sp | jq '.appId')
clientSecret=$(echo $sp | jq '.password')

# create the aks-engine
bash aks-engine.sh --subscription-id "<subscriptionId>" --client-id "<clientId>" --client-secret "<clientSecret>" --dns-prefix "<clusterDnsPrefix>" --location "<location>"
```

## ARO v4 Cluster

Azure Redhat Openshift v4 cluster can be created with below command.

> Note: Because of the cleanup policy on internal subscriptions, cluster creation can fail if you dont change cleanup service to none on the subnets of aro vnet before creation.
```
bash aro-v4.sh --subscription-id "<subscriptionId>" --resource-group "<rgName>" --cluster-name "<clusterName>" --location "<location>"
```
## Azure Arc K8s cluster

you can connect on-prem k8s cluster or unmanaged k8s cluster such as aks-engine to azure through azure arc.

```
bash arc-k8s-cluster.sh --subscription-id "<subId>" --resource-group "<rgName>" --cluster-name "<clusterName>" --location "<location>" --kube-context "<contextofexistingcluster>"
```
