##  ContainerLogV2 Queries

# 1. Container Logs for Specific PodName, PodNamespace and ContainerName

``` bash
let startTime = ago(1h);
let endTime = now();
let clustereResourceId = "<clusterARMResourceId>";
let podNameSpace = "<PodNamespace>";
let podName = "<podName>";
let containerName = "<containerName>";

ContainerLogV2
| where TimeGenerated >= startTime and TimeGenerated < endTime
| where _ResourceId =~ clustereResourceId
| where PodNamespace == podNameSpace
| where PodName == podName
| where ContainerName == containerName
| project TimeGenerated, Computer, ContainerId, LogMessage, LogSource

```
# 2. Container Logs for Specific Deployment

``` bash
let startTime = ago(1h);
let endTime = now();
let clustereResourceId = "<clusterARMResourceId>";
let deploymentNamespace = "<deploymentNamespace>";
let deploymentName = "<deploymentName>";

let KubePodInv = KubePodInventory
| where TimeGenerated >= startTime and TimeGenerated < endTime
| where _ResourceId =~ clustereResourceId
| where Namespace == deploymentNamespace
| where ControllerKind == "ReplicaSet"
| extend deployment = reverse(substring(reverse(ControllerName), indexof(reverse(ControllerName), "-") + 1))
| where deployment == deploymentName
| extend ContainerId = ContainerID
| summarize arg_max(TimeGenerated, *)  by deployment, ContainerId, PodStatus, ContainerStatus
| project deployment, ContainerId, PodStatus, ContainerStatus;


KubePodInv
| join
(
    ContainerLogV2
  | where TimeGenerated >= startTime and TimeGenerated < endTime
  | where PodNamespace == deploymentNamespace
  | where PodName startswith deploymentName
) on ContainerId
| project TimeGenerated, deployment, PodName, PodStatus, ContainerName, ContainerId, ContainerStatus, LogMessage, LogSource

```

# 3. Container Logs for Versioned deployment

``` bash
    let startTime = ago(1h);
    let endTime = now();
    let clustereResourceId = "<clusterARMResourceId>";
    let deploymentNamespace = "<deploymentName>";
    let deploymentNamePrefix = "<deploymentNamePrefix>";
    let versionLabelKeyName = "version"; # update the version label key if its different

    let KubePodInv = KubePodInventory
    | where TimeGenerated >= startTime and TimeGenerated < endTime
    | where _ResourceId =~ clustereResourceId
    | where Namespace == deploymentNamespace
    | where ControllerKind == "ReplicaSet"
    | extend deployment = reverse(substring(reverse(ControllerName), indexof(reverse(ControllerName), "-") + 1))
    | where deployment startswith  deploymentNamePrefix
    | extend ContainerId = ContainerID
    | summarize arg_max(TimeGenerated, *)  by deployment, ContainerId, PodStatus, ContainerStatus, PodLabel
    | project deployment, ContainerId, PodStatus, ContainerStatus, PodLabel;

    KubePodInv
    | join
    (
        ContainerLogV2
    | where TimeGenerated >= startTime and TimeGenerated < endTime
    | where PodNamespace == deploymentNamespace
    | where PodName startswith deploymentNamePrefix
    ) on ContainerId
    | extend LabelsJSON = parse_json(PodLabel)
    | project TimeGenerated, deployment,  deploymentVersion = LabelsJSON.[0].[versionLabelKeyName], PodName, PodStatus, ContainerName, ContainerId, ContainerStatus, LogMessage, LogSource

```

# 4. Container Logs for Specific Controller

``` bash
    let startTime = ago(1h);
    let endTime = now();
    let clustereResourceId = "<clusterARMResourceId>";
    let controllerNamespace = "<controllerNamespace>";
    let controllerNamePrefix = "<controllerNamePrefix>";


    let KubePodInv = KubePodInventory
    | where TimeGenerated >= startTime and TimeGenerated < endTime
    | where _ResourceId =~ clustereResourceId
    | where Namespace == controllerNamespace
    | where ControllerName startswith controllerNamePrefix
    | extend ContainerId = ContainerID
    | summarize arg_max(TimeGenerated, *)  by ControllerKind, ControllerName, ContainerId, PodStatus, ContainerStatus
    | project ControllerKind, ControllerName, ContainerId, PodStatus, ContainerStatus;


    KubePodInv
    | join
    (
        ContainerLogV2
    | where TimeGenerated >= startTime and TimeGenerated < endTime
    | where PodNamespace == controllerNamespace
    | where PodName startswith controllerNamePrefix
    ) on ContainerId
    | project TimeGenerated, ControllerKind, ControllerName, PodName, PodStatus, ContainerName, ContainerId, ContainerStatus, LogMessage, LogSource

```

# 5. Container Logs of Any Failed Pod in Specified Namespace

``` bash
    let startTime = ago(4h);
    let endTime = now();
    let clustereResourceId = "<clusterARMResourceId>";
    let podNamespace = "<podNamespace>";

    let KubePodInv = KubePodInventory
    | where TimeGenerated >= startTime and TimeGenerated < endTime
    | where _ResourceId =~ clustereResourceId
    | where Namespace == podNamespace
    | where PodStatus == "Failed"
    | extend ContainerId = ContainerID
    | summarize arg_max(TimeGenerated, *)  by  ContainerId, PodStatus, ContainerStatus
    | project ContainerId, PodStatus, ContainerStatus;

    KubePodInv
    | join
    (
        ContainerLogV2
    | where TimeGenerated >= startTime and TimeGenerated < endTime
    | where PodNamespace == podNamespace
    ) on ContainerId
    | project TimeGenerated, PodName, PodStatus, ContainerName, ContainerId, ContainerStatus, LogMessage, LogSource

```