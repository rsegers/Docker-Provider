@description('Cluster Name')
param clusterName string 

@description('ContainerInsights extension association name')
param associationName string 

@description('Data collection rule Id')
param dataCollectionRuleId string 

resource variables_clusterName_microsoft_insights_variables_association 'Microsoft.ContainerService/managedClusters/providers/dataCollectionRuleAssociations@2021-04-01' = {
  name: '${clusterName}/microsoft.insights/${associationName}'
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster.'
    dataCollectionRuleId: dataCollectionRuleId
  }
}
