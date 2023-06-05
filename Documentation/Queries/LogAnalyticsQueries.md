##  ContainerLogV2 Queries

# 1. Container Logs (StdOut or StdErr) for Specific PodName, PodNamespace and ContainerName

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
| project TimeGenerated, Computer, ContainerId, LogMessage

```
# 1. Container Logs (StdOut or StdErr) for Specific deployment


# 2. Container Logs of System Pods

# 3. Container Logs (StdOut or StdErr) for Specific K8s Deployment

# 4. Container Logs (StdOut or StdErr) for failed Pod



