module HealthModel
    class MonitorState
        CRITICAL = "fail"
        ERROR = "err"
        WARNING = "warn"
        NONE = "none"
        HEALTHY = "pass"
        UNKNOWN = "unknown"
    end

    class AggregationAlgorithm
        WORSTOF = "worstOf"
        PERCENTAGE = "percentage"
    end

    class MonitorId
        CLUSTER = 'cluster';
        ALL_NODES = 'all_nodes';
        K8S_INFRASTRUCTURE = 'k8s_infrastructure'

        NODE = 'node';
        AGENT_NODE_POOL = 'agent_node_pool'
        MASTER_NODE_POOL = 'master_node_pool'
        ALL_AGENT_NODE_POOLS = 'all_agent_node_pools'
        ALL_NODE_POOLS = 'all_node_pools';

        WORKLOAD = 'all_workloads';
        CAPACITY = 'capacity';

        USER_WORKLOAD = 'user_workload';
        SYSTEM_WORKLOAD = 'system_workload'
        NAMESPACE = 'namespace';
    end

    class HealthMonitorRecordFields
        CLUSTER_ID = "ClusterId"
        MONITOR_ID = "MonitorId"
        MONITOR_INSTANCE_ID = "MonitorInstanceId"
        MONITOR_LABELS = "MonitorLabels"
        DETAILS = "Details"
        MONITOR_CONFIG = "MonitorConfig"
        OLD_STATE = "OldState"
        NEW_STATE = "NewState"
        AGENT_COLLECTION_TIME = "AgentCollectionTime"
        TIME_FIRST_OBSERVED = "TimeFirstObserved"
        NODE_NAME = "NodeName"
        NAMESPACE = "Namespace"
    end

    class HealthMonitorConstants
        NODE_CPU_MONITOR_ID = "node_cpu_utilization"
        NODE_MEMORY_MONITOR_ID = "node_memory_utilization"
        CONTAINER_CPU_MONITOR_ID = "container_cpu_utilization"
        CONTAINER_MEMORY_MONITOR_ID = "container_memory_utilization"
        NODE_CONDITION_MONITOR_ID = "node_condition"
        WORKLOAD_CPU_OVERSUBSCRIBED_MONITOR_ID = "subscribed_capacity_cpu"
        WORKLOAD_MEMORY_OVERSUBSCRIBED_MONITOR_ID = "subscribed_capacity_memory"
        WORKLOAD_CONTAINER_CPU_PERCENTAGE_MONITOR_ID = "container_cpu_utilization"
        WORKLOAD_CONTAINER_MEMORY_PERCENTAGE_MONITOR_ID = "container_memory_utilization"
        KUBE_API_STATUS = "kube_api_status"
        USER_WORKLOAD_PODS_READY_MONITOR_ID = "user_workload_pods_ready"
        SYSTEM_WORKLOAD_PODS_READY_MONITOR_ID = "system_workload_pods_ready"
    end

    class HealthMonitorStates
        PASS = "pass"
        FAIL = "fail"
        WARNING = "warn"
        NONE = "none"
        UNKNOWN = "unknown"
    end

    class HealthMonitorLabels
        WORKLOAD_NAME = "container.azm.ms/workload-name"
        WORKLOAD_KIND = "container.azm.ms/workload-kind"
        NAMESPACE = "container.azm.ms/namespace"
        AGENTPOOL = "agentpool"
        ROLE = "kubernetes.io/role"
        HOSTNAME = "kubernetes.io/hostname"
    end
end