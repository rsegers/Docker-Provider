# Onboarding Instructions

This feature enables the ingestion of the Container Std{out;err} logs to Geneva Logs Account in single & multi-tenancy modes.
In single tenancy mode, Container Std{out;err} logs from the containers in all the Kubernetes namespaces will ingested to single Geneva Logs Account where as
in case of multi-tenancy mode, Container Std{out;err} logs from one or more K8s namespace can be ingested to corresponding Geneva Logs Account.

## 1. Geneva Logs Account Configuration

  1. Create Geneva Logs Account if you dont have one to use
  2. Navigate to [GenevaLogs Account](https://portal.microsoftgeneva.com/account/logs/configurations)
  3. Update namespace, account, moniker & identity values in [AGENTCONFIG](./ContainerLogV2.xml) corresponding to your geneva Logs account
     > Both account and moniker should have the same value of storage group name (i.e. moniker)
     > If you dont have Account Moniker, you can create one by creating storage group from Resources tab of Geneva Logs Account
  4. Upload this updated configuration to your Geneva Logs Account

### 2a. Managed Identity Auth for Single Tenancy Mode

  1. Get the ObjectId of Managed Identity & Tenant Id of the your AKS cluster through

      ``` bash
         az account set -s  <AKS cluster Azure Subscription Id>
         az account show | grep -i tenantId
         az aks show -g <AKS Cluster RG> -n <AKS ClusterName> | grep -i kubeletidentity
         az aks show -g <AKS Cluster RG> -n <AKS ClusterName> | grep -i KubeletIdentity -A 5 | grep -i objectId
      ```
  2. Navigate to [GenevaLogs Account](https://portal.microsoftgeneva.com/account/logs/configurations)
  3. Select Logs Endpoint & Account Name, then select User Roles
  4. Select the Managed Certificates option on _MaCommunication Role
  5. Add ObjectId & TenantId obtained in above step to under Managed Identity (Preview) option

### 2b. Managed Identity Auth for Multi-tenancy Tenancy Mode

  1. Get the  Tenant Id of the your AKS cluster through
     ``` bash
       az account set -s  <AKS cluster Azure Subscription Id>
       az account show | grep -i tenantId
     ```
  2. Get the ObjectId of Managed Identity AKS cluster corresponding your each Kubernetes namespace
      > Note: Refer to AAD Pod Managed Identity or AAD Workload Identity Public documentation how to obtain
  3. Navigate to corresponding [GenevaLogs Account](https://portal.microsoftgeneva.com/account/logs/configurations)
  4. Select Logs Endpoint & Account Name, then select User Roles
  5. Select the Managed Certificates option on _MaCommunication Role
  6. Add ObjectId & TenantId obtained in above step to under Managed Identity (Preview) option and save this configuration

## 3. AKS Monitoring Addon Enablement

1. Enable  AKS Monitoring addon to your AKS cluster if you havent enabled already
     ``` bash
       az account set -s  <AKS cluster Azure Subscription Id>
       az aks enable-addons -a monitoring -g <AKS ClusterResourceGroup> -n <AKS ClusterName>
    ```
## 3a. Configuring the AKS Monitoring Addon for Single Tenancy Mode

 1. Download the [AgentConfigMap](../../kubernetes/container-azm-ms-agentconfig.yaml)
 2. Update below settings under `integrations.geneva_logs` in downloaded configmap
    ``` bash
        enabled = true
        environment = "<geneva logs account environment name>"
        namespace = "<geneva logs account namespace>"
        account = "<geneva logs account name>"
        region = "<geneva logs gcs region>"
        configversion = "1.0" # current supported version
    ```
  3. Apply the configmap to your AKS cluster via `kubectl apply -f container-azm-ms-agentconfig.yaml`

## 3b. Configuring the AKS Monitoring Addon for Multi Tenancy Mode

  1. Deploy the AMA Logs Geneva Service to your Kubernetes namespace through

     ``` bash
      export  HELM_EXPERIMENTAL_OCI=1
      # pull chart  from MCR registry
      helm chart pull  mcr.microsoft.com/azuremonitor/containerinsights/preview/azuremonitor-containers:0.1.0
      # export the chart to local directory
      helm chart export mcr.microsoft.com/azuremonitor/containerinsights/preview/azuremonitor-containers:0.1.0
      # update the parameters and install the chart
      helm upgrade --install  azuremonitor-containers-geneva  --set genevaLogsConfig.aadpodidbinding=<aadpodbindingname>,genevaLogsConfig.configversion=1.0,genevaLogsConfig.authid=object_id#<ObjectIdOfTheManagedIdentity>,genevaLogsConfig.environment=<environment>,genevaLogsConfig.account=<accountName>,genevaLogsConfig.namespace=<namespace>,genevaLogsConfig.region=<region> -n <K8sNamespace> azuremonitor-containers/

     ```
 2. Download the [AgentConfigMap](../../kubernetes/container-azm-ms-agentconfig.yaml)
 3. Update below settings under `integrations.geneva_logs` in downloaded configmap

    ``` bash
        enabled = true
        # # when the multitenancy is true, container logs of the specific k8s namespace will be routed to corresponding geneva telemetry service endpoint
        # # logs of the infra namespaces if infra_namespaces_suffix specified, ingested to geneva account defined in this config
        multi_tenancy = true
        # infra_namespaces = ["cosmic-infra-*", "gate-keeper-system", "kube-system"]
        # # logs of the tenant namespaces will be routed to k8s service in corresponding namespace
        # # for example tenant namespaces are tenant1, tenant2, then logs of tenant1 will be routed to genevatelemeyservice.tenant1.svc.cluster.local endpoint
        # # and logs of tenant2 will be routed genevatelemeyservice.tenant2.svc.cluster.local endpoint
        # geneva telemetry service needs to be defined
        tenant_namespaces = ["tenant1", "tenant2", "tenant3"]
    ```
  4. For very high volume log collection, recommended to use below settings under `agent_settings.fbit_config` in the configmap to avoid the log loss

     ``` bash
         log_flush_interval_secs = "1"                 # default value is 15
         tail_mem_buf_limit_megabytes = "2000"         # default value is 10
         tail_buf_chunksize_megabytes = "10"           # default value is 32kb
         tail_buf_maxsize_megabytes = "20"             # defautl value is 32kb
     ```
  5. Apply the configmap to your AKS cluster via `kubectl apply -f container-azm-ms-agentconfig.yaml`

## Validation

1. Navigate to [Dgrep](https://portal.microsoftgeneva.com/logs/dgrep) and select the Endpoint, Namespace & select the ContainerLogV2Event to see the container logs getting ingested
  > Note: If you want the logs of the containers in kube-system namespace, remove the kube-system from exclude_namespaces in the container-azm-ms-agentconfig.yaml and apply the yaml via `kubectl apply -f container-azm-ms-agentconfig.yaml`
2. Navigate to Insights page of your AKS cluster to view charts and other experience
