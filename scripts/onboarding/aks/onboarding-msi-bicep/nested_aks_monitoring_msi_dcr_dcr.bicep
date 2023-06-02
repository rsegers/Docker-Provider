@description('Data collection rule name')
param dcrName string

@description('Workspace Region for data collection rule')
param workspaceRegion string

@description('Existing or new tags to use on AKS, ContainerInsights and DataCollectionRule Resources')
param resourceTagValues object

@description('Data collection interval e.g. "5m" for metrics and inventory. Supported value range from 1m to 30m')
param dataCollectionInterval string

@description('Data collection Filtering Mode for the namespaces')
@allowed([
  'Off'
  'Include'
  'Exclude'
])
param namespaceFilteringModeForDataCollection string

@description('An array of Kubernetes namespaces for the data collection of inventory, events and metrics')
param namespacesForDataCollection array

@description('Full Resource ID of the log analitycs workspace that will be used for data destination. For example /subscriptions/00000000-0000-0000-0000-0000-00000000/resourceGroups/ResourceGroupName/providers/Microsoft.operationalinsights/workspaces/ws_xyz')
param workspaceResourceId string

resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrName
  location: workspaceRegion
  tags: resourceTagValues
  kind: 'Linux'
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          streams: [
            'Microsoft-ContainerInsights-Group-Default'
          ]
          extensionSettings: {
            dataCollectionSettings: {
              interval: dataCollectionInterval
              namespaceFilteringMode: namespaceFilteringModeForDataCollection
              namespaces: namespacesForDataCollection
            }
          }
          extensionName: 'ContainerInsights'
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceResourceId
          name: 'ciworkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ContainerInsights-Group-Default'
        ]
        destinations: [
          'ciworkspace'
        ]
      }
    ]
  }
}
