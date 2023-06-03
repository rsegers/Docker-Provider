@description('ContainerInsights extension association name')
param associationName string 

@description('Data collection rule Id')
param dataCollectionRuleId string 

@description('Cluster name')
param clusterName string 

@description('Cluster Location')
param clusterLocation string 

resource clusterName_microsoft_insights_association 'Microsoft.ContainerService/managedClusters/providers/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${clusterName}/microsoft.insights/${associationName}'
  location: clusterLocation
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster.'
    dataCollectionRuleId: dataCollectionRuleId
  }
}
