# Onboarding Instructions
This feature enables the ingestion of the Container Std{out;err} logs to Geneva Logs Account and all other types gets ingested to Azure Log Analytics Workspace.

## Geneva Logs Account Configuration

1. Create Geneva Logs Account if you dont have one to use for testing of this feature
2. Navigate to [GenevaLogs Account](https://portal.microsoftgeneva.com/account/logs/configurations)
     -  2.1. Select Logs Endpoint & Account Name, then select User Roles
     -  2.2. Select the Managed Certificates option on _MaCommunication Role
     -  2.3. Add the ObjectId & TenantId of the User Assigned Identity on AKS cluster VMSS
           > Note: you can get the ObjectId of the UAI assigned to VMSS in MC_ Resource Group of the AKS cluster from Identity tab
           > Note: if you want to use new UAI, create one and assign the cluster nodes and use that Geneva Logs Account
3. Replace the namespace & geneva account moniker values in [AGENTCONFIG](./mdsdconfig-v2.xml) and upload to configuration in Geneva Logs Account
   > If you dont have Account Moniker, you can create one by creating storage group from Resources tab of Geneva Logs Account

## AKS Monitoring Addon Enablement

1. Download the [AgentConfigMap](../../kubernetes/container-azm-ms-agentconfig.yaml)
2. Update settings under `agent_settings.geneva_logs_config` in downloaded configmap with Geneva Account configuration (Environment, Namespace, Account & AuthId)
3. Apply the configmap to your AKS cluster via `kubectl apply -f container-azm-ms-agentconfig.yaml`
4. Download the [AgentYaml](../../kubernetes/omsagent.yaml)
5. Replace all the placeholders - WSID, KEY, AKS_RESOURCE_ID & AKS_REGION values in downaloaded omsagent.yaml
   > Note: WSID & Key can be obtained from Azure Portal via Log Analytics Workspace and then Agent configuration.Values obtained from Azure Portal needs to base64 encoded again to put into the yaml
6. Apply the yaml via `kubectl apply -f omsagent.yaml`
7. Download onboarding ARM templates [TemplateParameterFile](./existingClusterOnboarding.json) and [TemplateFile](./existingClusterOnboarding.json)
8. Update place holder values of aksResourceId, aksResourceLocation & workspaceResourceId with actual values in downloaded Parameter file
9. Deploy the below ARM template to get Azure Portal AKS Insights Experience working
     ```bash
       az group deployment create --resource-group <resourceGroupNameofCluster> --template-file ./existingClusterOnboarding.json --parameters @./existingClusterParam.json
     ```
10. For Monitoring data to flow to Log Analytics Workspace, ContainerInsights solution required on the Log Analytics Workspace. Follow the [instructions](../../scripts/onboarding/solution-onboarding.md) to add the solution

## Validation

1. Navigate to [Dgrep](https://portal.microsoftgeneva.com/logs/dgrep) and select the Endpoint, Namespace & select the ContainerLogV2Event to see the container logs getting ingested
  > Note: By default, container std{out;err} logs of the container in kube-system namespace excluded. If you want the logs of the containers in kube-system namespace, remove the kube-system from exclude_namespaces in the container-azm-ms-agentconfig.yaml and apply the yaml via `kubectl apply -f container-azm-ms-agentconfig.yaml`
2. Navigate to Insights page of your AKS cluster to view charts and other experience
