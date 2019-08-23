require_relative 'health_model_constants'

module HealthModel
    class AggregateMonitorInstanceIdLabels
        @@id_labels_mapping = {
            MonitorId::SYSTEM_WORKLOAD => [HealthMonitorLabels::NAMESPACE, HealthMonitorLabels::WORKLOAD_NAME],
            MonitorId::USER_WORKLOAD => [HealthMonitorLabels::NAMESPACE, HealthMonitorLabels::WORKLOAD_NAME],
            MonitorId::NODE => [HealthMonitorLabels::AGENTPOOL, HealthMonitorLabels::ROLE, HealthMonitorLabels::HOSTNAME],
            MonitorId::NAMESPACE => [HealthMonitorLabels::NAMESPACE],
            MonitorId::AGENT_NODE_POOL => [HealthMonitorLabels::AGENTPOOL],
            # MonitorId::ALL_AGENT_NODE_POOLS => [],
            # MonitorId::ALL_NODE_POOLS => [],
            # MonitorId::ALL_NODES => [],
            # MonitorId::K8S_INFRASTRUCTURE => [],
            # MonitorId::CLUSTER => [],
            # MonitorId::WORKLOAD => []
        }

        def self.get_labels_for(monitor_id)
            if @@id_labels_mapping.key?(monitor_id)
                return @@id_labels_mapping[monitor_id]
            else
                return []
            end

        end
    end
end