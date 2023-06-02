@description('ContainerInsights extension association name')
param associationName string 

@description('Data collection rule Id')
param dataCollectionRuleId string 

resource clusterName_microsoft_insights_association 'microsoft.insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: associationName
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster.'
    dataCollectionRuleId: dataCollectionRuleId
  }
}
