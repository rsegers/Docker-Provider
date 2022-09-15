# Instructions for Azure Managed Service for Prometheus Private Preview onboarding - Alert and recording rules

**NOTE**
You should start onboarding alert and recording rules after successfully completing onboarding to the [Azure Managed Service for Prometheus private preview](https://github.com/microsoft/Docker-Provider/blob/prometheus-collector/prometheus-collector/MAC-3P-Docs/Instructions%20for%20Private%20Preview%20Onboarding.md).

## Overview

### Prometheus rule groups

Prometheus alert rules and recording rules are configured as part of a **rule group**. Rules within a group are run sequentially in the order they are defined in the group. In the private preview, rule groups, recording rules and alert rules are configured using Azure Resource Manager (ARM) templates, API and provisioning tools. A new ARM resource called Prometheus Rule Group is now added to ARM. Users can create and configure rule group resources, where the alert rules and recording rules are defined as part of the rule group properties. Azure Prometheus rule groups are defined with a scope of a specific Azure **Monitoring Account (MAC)**.

### Prometheus alert rules

Prometheus **alert rules** allow you to define alert conditions, using queries which are written in Prometheus Query Language (Prom QL) that are applied on Prometheus metrics stored in your **Monitoring Account (MAC)**. Whenever the alert query results in one or more time series meeting the condition, the alert counts as pending for these metric and label sets. A pending alert becomes active after a user-defined period of time during which all the consecutive query evaluations for the respective time series meet the alert condition. Once an alert becomes active, it is fired and would trigger your actions or notifications of choice, as defined in the [Azure Action Groups](https://docs.microsoft.com/azure/azure-monitor/alerts/action-groups) configured in your alert rule.

### Prometheus recording rules

**Recording rules** allow you to pre-compute frequently needed or computationally expensive expressions and save their result as a new set of time series. Querying the precomputed result will then often be much faster than executing the original expression every time it is needed. This is especially useful for dashboards, which need to query the same expression repeatedly every time they refresh, or for use in alert rules, where multiple alert rules may be based on the same complex query. Time series created by recording rules are ingested back to your Monitoring Account as new Prometheus metrics.

## Prometheus alerts and recording rules - private preview onboarding guidelines

### Supported regions

Prometheus alerts and recording rules is a regional service, therefore your alert and recording rules must reside in the same Azure region where your Monitoring Account (MAC) is defined. For the private preview, the following regions are supported:

* East US
* East US 2
* West Europe

### Prerequisites for private preview

Before onboarding to Prometheus alerts and recording rules:

* Your subscription needs to be registered and enabled for the Azure Managed Service for Prometheus private preview
* you need to complete onboarding to the [Azure Managed Service for Prometheus private preview](https://github.com/microsoft/Docker-Provider/blob/prometheus-collector/prometheus-collector/MAC-3P-Docs/Instructions%20for%20Private%20Preview%20Onboarding.md), including a successful creation of a Monitoring Account (MAC).

### Creating Prometheus rule groups with Azure Resource Manager (ARM) template

You can use an Azure Resource Manager template to create and configure Prometheus rule groups, alert rules and recording rules. Resource Manager templates enable you to programmatically set up alert and recording rules in a consistent and reproducible way across your environments.

The basic steps are as follows:

1. Use the templates below as a JSON file that describes how to create the rule group.
2. Deploy the template using any deployment method, such as Azure CLI, Azure Powershell, or ARM Rest APIs.

### Template example for a Prometheus rule group

To create a Prometheus rule group using a Resource Manager template, you create a resource of type Microsoft.AlertsManagement/prometheusRuleGroups and fill in all related properties. Azure Resource Manager template for a Prometheus rule group configures the group, and one or more alert rules and/or recording rules within the group. Note that alert rules and recording rules are executed in the order they appear within a group. Below is a sample template that creates a Prometheus rule group, including one recording rule and one alert rule.

Save the json below as samplePromRuleGroup.json for the purpose of this walkthrough.

```json
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "variables": {},
    "resources": [
        {
           "name": "sampleRuleGroup",
           "type": "Microsoft.AlertsManagement/prometheusRuleGroups",
           "apiVersion": "2021-07-22-preview",
           "location": "eastus",
           "properties": {
                "description": "Sample Prometheus Rule Group",
                "scopes": [
                    "/subscriptions/<subscriptionId>/resourcegroups/<resourceGroupName>/providers/microsoft.monitor/accounts/<monitoringAccountId>"
                ],
                "interval": "PT1M",
                "enabled": true,
                "clusterName": "<myClusterName>",
                "rules": [
                    {
                        "record": "instance:node_cpu_utilisation:rate5m",
                        "expression": "1 - avg without (cpu) (sum without (mode)(rate(node_cpu_seconds_total{job=\"node\", mode=~\"idle|iowait|steal\"}[5m])))",
                        "enabled": true
                    },
                    {
                        "alert": "KubeCPUQuotaOvercommit",
                        "expression": "sum(min without(resource) (kube_resourcequota{job=\"kube-state-metrics\", type=\"hard\", resource=~\"(cpu|requests.cpu)\"})) /  sum(kube_node_status_allocatable{resource=\"cpu\", job=\"kube-state-metrics\"}) > 1.5",
                        "for": "PT5M",
                        "labels": {
                            "team": "prod"
                        },
                        "annotations": {
                            "description": "Cluster has overcommitted CPU resource requests for Namespaces.",
                            "runbook_url": "https://github.com/kubernetes-monitoring/kubernetes-mixin/tree/master/runbook.md#alert-name-kubecpuquotaovercommit",
                            "summary": "Cluster has overcommitted CPU resource requests."
                        },
                        "enabled": true,
                        "severity": 3,
                        "resolveConfiguration": {
                            "autoResolved": true,
                            "timeToResolve": "PT10M"
                        },
                        "actions": [
                            {
                               "actionGroupId": "/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/microsoft.insights/actiongroups/<actionGroupName>"
                            }
                        ]
                    }
                ]
            }
        }
    ]
}        
```

The following table provides an explanation of the schema and properties for a Prometheus rule group.

| Name                 | Required  | Type | Description | Notes
| ----------------     | --------  | ---- | ----------- | -----
| name                 | True      | string | Prometheus rule group name | |
| location             | True      | string | Resource location | From regions supported in the preview |
| properties.description | False | string | Rule group description | |
| properties.scopes | True | string[] | Target Monitoring Account (MAC) | Only one scope currently supported |
| properties.enabled | False | boolean | Enable / diable group | default = false |
| properties.clusterName | False | string | Apply rule to data from a specific cluster | Default = no cluster limit (apply to all data in workspace) <sup>(1)</sup> |
| properties.interval | False | string | Group evaluation interval | Default = PT1M |
| rules.record | False | string | Recording rule name | Required for recording rules <sup>(2)</sup> |
| rules.alert  | False | string | Alert rule name | Required for alert rules <sup>(2)</sup> |
| rules.expression | True | string | PromQL expression | Prometheus rule 'expr' clause |
| rules.for | False | string | Alert firing timeout | Prometheus alert rule 'for' clause. Values - 'PT1M', 'PT5M' etc. |
| rules.labels | False | object | labels key-value pairs | Prometheus alert rule labels |
| rules.annotations | False | object | Annotations key-value pairs | Prometheus alert rule annotations |
| rules.severity | False | integer | Alert severity | 0-4, default is 3 (informational) |
| rules.resolveConfigurations.autoResolved | False | boolean | Alert auto resolution enabled | Default = true |
| rules.resolveConfigurations.timeToResolve | False | string | Alert auto resolution timeout | Default = "PT5M" |
| rules.action[].actionGroupId | false | string | action group id | the array of actions that are performed when an alert is fired or resolved |

Notes:

<sup>(1)</sup> Use 'clusterName' to apply the rule group to the data from a specific cluster. The "clusterName" value must be identical to the 'Cluster' label used on the metrics from this cluster.
<sup>(2)</sup> Each rule must include either 'record' or 'alert' (but not both)

### Limiting rules to a specific cluster

As an option, you can limit the rules in a rule group to query data originating from a specific cluster, using  the rule group **clusterName**  property.
As a best practice, it is recommended to limit rules to a single cluster if your MAC contains a large scale of data from multiple clusters, and there is a concern that running a single set of rules on all the data may cause performance or throttling issues. Using the clusterName property, you can create multiple rule groups, each configured with the same rules, limiting each group to cover a different cluster. 

Notes:
* The **clusterName** value must be identical to the **cluster** label that is added to the metrics from a specific cluster during data collection.
* If clusterName is not specified for a specific rule group, the rules in the group will query all the data in the MAC (from all clusters).

### Deployment of Prometheus rule groups using Azure CLI

To deploy a Prometheus rule group template stored on your local Windows computer using Azure CLI, use the following steps.

1. Open windows CMD

2. Login /authenticate to Azure

3. Select subscription (note: subscription must be registered to the private preview)

4. Deploy template (use the local path for your template). Note the rule group name is set in the template.

5. (Optional) check updated rule group (use the name you set in the template)

```azurecli
az Login
az account set --subscription <subscription name>
az deployment group create --resource-group <resource group name> --template-file <template-path/name> 
az resource show --ids /subscriptions/<subscriptionId>/resourceGroups/<resource group name>/providers/Microsoft.AlertsManagement/prometheusRuleGroups/<rule group name>
```
To modify an existing rule group in your subscription, edit the template file and repeat the deployment procedure above using the deployed template.

## Prometheus alerts and the Azure portal

You can now view fired and resolved Prometheus alerts in the Azure portal, similar to other alert types.

1. In Azure Monitor, select **Alerts** in the left-side menu to see the list of alerts fired and/or resolved.
2. Set the list filter 'Monitoring Service' to 'Prometheus' to see Prometheus alerts (you may need to add the filter using the 'Add Filter' button). You can further set the filter 'Alert condition' to 'Fired', 'Resolved' or both, as required.

![Prometheus alert preview](https://github.com/microsoft/Docker-Provider/blob/prometheus-collector/prometheus-collector/MAC-3P-Docs/Prom%20alert%20list%20preview.png)

3. Click the alert name to view the details of a specific fired/resolved alert.

![Prometheus alert details](https://github.com/microsoft/Docker-Provider/blob/prometheus-collector/prometheus-collector/MAC-3P-Docs/Prom%20alert%20details.png)

**Note**
In the preview, editing of rules and rule groups via the portal UI is not supported.
