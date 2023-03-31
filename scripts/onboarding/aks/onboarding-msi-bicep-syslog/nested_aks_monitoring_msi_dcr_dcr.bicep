@description('Data collection rule name')
param dcrName string

@description('Workspace Region for data collection rule')
param workspaceRegion string

@description('Existing or new tags to use on AKS, ContainerInsights and DataCollectionRule Resources')
param resourceTagValues object

@description('Array of allowed syslog facilities')
param syslogFacilities array

@description('Array of allowed syslog levels')
param syslogLevels array

@description('Full Resource ID of the log analitycs workspace that will be used for data destination. For example /subscriptions/00000000-0000-0000-0000-0000-00000000/resourceGroups/ResourceGroupName/providers/Microsoft.operationalinsights/workspaces/ws_xyz')
param workspaceResourceId string

resource dcr 'Microsoft.Insights/dataCollectionRules@2021-04-01' = {
  name: dcrName
  location: workspaceRegion
  tags: resourceTagValues
  kind: 'Linux'
  properties: {
    dataSources: {
      syslog: [
        {
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: syslogFacilities
          logLevels: syslogLevels
          name: 'sysLogsDataSource'
        }
      ]
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          streams: [
            'Microsoft-ContainerInsights-Group-Default'
          ]
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
          'Microsoft-Syslog'
        ]
        destinations: [
          'ciworkspace'
        ]
      }
    ]
  }
}
