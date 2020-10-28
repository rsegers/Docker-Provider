# Onboard to Azure Monitor for containers Health(Tab) limited preview

For on-boarding to Health(Tab), you would need to complete two steps
1. Configure agent through configmap to collect health data. [Learn more about ConfigMap](https://docs.microsoft.com/azure/azure-monitor/insights/container-insights-agent-config#configmap-file-settings-overview)
2. Access Health(Tab) in Azure Monitor for Containers Insights experience in portal with feature flag URL. [aka.ms/HealthPreview](https://aka.ms/Healthpreview)


## Configure agent through ConfigMap
1. If you are configuring your existing ConfigMap, append the following section in your existing ConfigMap yaml file
```
#Append this section in your existing configmap
agent-settings: |-
       # agent health model feature settings   
    [agent_settings.health_model]   
      # In the absence of this configmap, default value for enabled is false   
      enabled = true
```
2. Else if you don't have ConfigMap, download the new ConfigMap from [here.](https://github.com/microsoft/Docker-Provider/blob/ci_prod/kubernetes/container-azm-ms-agentconfig.yaml) & then set `enabled =true`
      
```
#For new downloaded configmap enabled this default setting to true
agent-settings: |-
       # agent health model feature settings   
    [agent_settings.health_model]   
      # In the absence of this configmap, default value for enabled is false   
      enabled = true
```


3. Run the following kubectl command:
   `kubectl apply -f <configmap_yaml_file.yaml>`
   
Example: `kubectl apply -f container-azm-ms-agentconfig.yaml`.

The configuration change can take a few minutes to finish before taking effect, and all omsagent pods in the cluster will restart. The restart is a rolling restart for all omsagent pods, not all restart at the same time.


## Access health(tab) in Azure Monitor for containers Insights experience
1. You can view Health(tab) by accessing portal through this link. [aka.ms/HealthPreview](https://aka.ms/Healthpreview). This URL includes required feature flag.


For any question please reachout to us at [askcoin@microsoft.com](mailto:askcoin@microsoft.com)

