@description('Cluster Name')
param clusterName string 

@description('Location of the AKS resource e.g. "East US"')
param aksResourceLocation string

@description('Existing or new tags to use on AKS, ContainerInsights and DataCollectionRule Resources')
param resourceTagValues object

@description('AKS Cluster Resource ID')
param aksResourceId string

@description('Full Resource ID of the log analitycs workspace that will be used for data destination. For example /subscriptions/00000000-0000-0000-0000-0000-00000000/resourceGroups/ResourceGroupName/providers/Microsoft.operationalinsights/workspaces/ws_xyz')
param workspaceResourceId string

resource variables_cluster 'Microsoft.ContainerService/managedClusters@2018-03-31' = {
  name: clusterName
  location: aksResourceLocation
  tags: resourceTagValues
  properties: {
    mode: 'Incremental'
    id: aksResourceId
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: workspaceResourceId
          useAADAuth: 'true'
        }
      }
    }
  }
}
