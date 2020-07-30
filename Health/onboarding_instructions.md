# Onboard to Azure Monitor for containers Health(Tab) limited preview

For on-boarding to Health(Tab), you would need to complete two steps
1. Configure agent through configmap to collect health data. [Learn more about ConfigMap](https://docs.microsoft.com/azure/azure-monitor/insights/container-insights-agent-config#configmap-file-settings-overview)
2. Access Health(Tab) in Azure Monitor for Containers Insights experience in portal with feature flag URL. [aka.ms/HealthPreview](https://aka.ms/Healthpreview)


## Configure agent through ConfigMap
1. Include the following section in ConfigMap yaml file
```cmd:agent-settings: |-
    [agent_settings.health_model]
      enabled = true
```
2. Run the following kubectl command:
   `kubectl apply -f <configmap_yaml_file.yaml>`
   
Example: `kubectl apply -f container-azm-ms-agentconfig.yaml`.

The configuration change can take a few minutes to finish before taking effect, and all omsagent pods in the cluster will restart. The restart is a rolling restart for all omsagent pods, not all restart at the same time.


## Access health(tab) in Azure Monitor for containers Insights experience
1. You can view Health(tab) by accessing portal through this link. [aka.ms/HealthPreview](https://aka.ms/Healthpreview). This URL includes required feature flag.


For any question please reachout to us at [askcoin@microsoft.com](mailto:askcoin@microsoft.com)

