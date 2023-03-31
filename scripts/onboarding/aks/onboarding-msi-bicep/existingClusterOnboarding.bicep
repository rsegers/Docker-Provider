@description('AKS Cluster Resource ID')
param aksResourceId string

@description('Location of the AKS resource e.g. "East US"')
param aksResourceLocation string

@description('Existing or new tags to use on AKS, ContainerInsights and DataCollectionRule Resources')
param resourceTagValues object

@description('Workspace Region for data collection rule')
param workspaceRegion string

@description('Full Resource ID of the log analitycs workspace that will be used for data destination. For example /subscriptions/00000000-0000-0000-0000-0000-00000000/resourceGroups/ResourceGroupName/providers/Microsoft.operationalinsights/workspaces/ws_xyz')
param workspaceResourceId string

@description('Data collection interval e.g. "5m" for metrics and inventory. Supported value range from 1m to 30m')
param dataCollectionInterval string

@description('Data collection Filtering Mode for the namespaces')
@allowed([
  'Off'
  'Include'
  'Exclude'
])
param namespaceFilteringModeForDataCollection string = 'Off'

@description('An array of Kubernetes namespaces for the data collection of inventory, events and metrics')
param namespacesForDataCollection array

var clusterSubscriptionId = split(aksResourceId, '/')[2]
var clusterResourceGroup = split(aksResourceId, '/')[4]
var clusterName = split(aksResourceId, '/')[8]
var dcrNameFull = 'MSCI-${workspaceRegion}-${clusterName}'
var dcrName = ((length(dcrNameFull) > 64) ? substring(dcrNameFull, 0, 64) : dcrNameFull)
var associationName = 'ContainerInsightsExtension'
var dataCollectionRuleId = resourceId(clusterSubscriptionId, clusterResourceGroup, 'Microsoft.Insights/dataCollectionRules', dcrName)

module aks_monitoring_msi_dcr_dcr './nested_aks_monitoring_msi_dcr_dcr.bicep' = {
  name: 'aks-monitoring-msi-dcr-${uniqueString(dcrName)}'
  scope: resourceGroup(clusterSubscriptionId, clusterResourceGroup)
  params: {
    dcrName: dcrName
    workspaceRegion: workspaceRegion
    resourceTagValues: resourceTagValues
    dataCollectionInterval: dataCollectionInterval
    namespaceFilteringModeForDataCollection: namespaceFilteringModeForDataCollection
    namespacesForDataCollection: namespacesForDataCollection
    workspaceResourceId: workspaceResourceId
  }
}

module aks_monitoring_msi_dcra_aksResourceId './nested_aks_monitoring_msi_dcra_aksResourceId.bicep' = {
  name: 'aks-monitoring-msi-dcra-${uniqueString(aksResourceId)}'
  scope: resourceGroup(clusterSubscriptionId, clusterResourceGroup)
  params: {
    associationName: associationName
    dataCollectionRuleId: dataCollectionRuleId
  }
  dependsOn: [
    aks_monitoring_msi_dcr_dcr
  ]
}

module aks_monitoring_msi_addon_aksResourceId './nested_aks_monitoring_msi_addon_aksResourceId.bicep' = {
  name: 'aks-monitoring-msi-addon-${uniqueString(aksResourceId)}'
  scope: resourceGroup(clusterSubscriptionId, clusterResourceGroup)
  params: {
    clusterName: clusterName
    aksResourceLocation: aksResourceLocation
    resourceTagValues: resourceTagValues
    workspaceResourceId: workspaceResourceId
  }
  dependsOn: [
    aks_monitoring_msi_dcra_aksResourceId
  ]
}
