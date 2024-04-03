package mdm

const (
	MDMOOMKilledContainerCount                          = "oomKilledContainerCount"
	MDMContainerRestartCount                            = "restartingContainerCount"
	MDMPodReadyPercentage                               = "podReadyPercentage"
	MDMStaleCompletedJobCount                           = "completedJobsCount"
	MDMDiskUsedPercentage                               = "diskUsedPercentage"
	MDMContainerCpuUtilizationMetric                    = "cpuExceededPercentage"
	MDMContainerMemoryRssUtilizationMetric              = "memoryRssExceededPercentage"
	MDMContainerMemoryWorkingSetUtilizationMetric       = "memoryWorkingSetExceededPercentage"
	MDMPvUtilizationMetric                              = "pvUsageExceededPercentage"
	MDMContainerCpuThresholdViolatedMetric              = "cpuThresholdViolated"
	MDMContainerMemoryRssThresholdViolatedMetric        = "memoryRssThresholdViolated"
	MDMContainerMemoryWorkingSetThresholdViolatedMetric = "memoryWorkingSetThresholdViolated"
	MDMPvThresholdViolatedMetric                        = "pvUsageThresholdViolated"
	MDMNodeCpuUsagePercentage                           = "cpuUsagePercentage"
	MDMNodeMemoryRssPercentage                          = "memoryRssPercentage"
	MDMNodeMemoryWorkingSetPercentage                   = "memoryWorkingSetPercentage"
	MDMNodeCpuUsageAllocatablePercentage                = "cpuUsageAllocatablePercentage"
	MDMNodeMemoryRssAllocatablePercentage               = "memoryRssAllocatablePercentage"
	MDMNodeMemoryWorkingSetAllocatablePercentage        = "memoryWorkingSetAllocatablePercentage"
	ContainerTerminatedRecentlyInMinutes                = 5
	ObjectNameK8SContainer                              = "K8SContainer"
	ObjectNameK8SNode                                   = "K8SNode"
	CPUUsageNanoCores                                   = "cpuUsageNanoCores"
	CPUUsageMilliCores                                  = "cpuUsageMillicores"
	MemoryWorkingSetBytes                               = "memoryWorkingSetBytes"
	MemoryRssBytes                                      = "memoryRssBytes"
	PVUsedBytes                                         = "pvUsedBytes"
	JobCompletionTime                                   = "completedJobTimeMinutes"
	DefaultMDMCpuUtilizationThreshold                   = 95.0
	DefaultMDMMemoryRssThreshold                        = 95.0
	DefaultMDMMemoryWorkingSetThreshold                 = 95.0
	DefaultMDMPvUtilizationThreshold                    = 60.0
	DefaultMDMJobCompletedTimeThresholdMinutes          = 360
	ControllerKindJob                                   = "job"
	ContainerTerminationReasonCompleted                 = "completed"
	ContainerStateTerminated                            = "terminated"
	TelegrafDiskMetrics                                 = "container.azm.ms/disk"
	AmaLogsZeroFill                                     = "ama-logs"
	KubesystemNamespaceZeroFill                         = "kube-system"
	VolumeNameZeroFill                                  = "-"
	// Telemetry constants
	ContainerMetricsHeartBeatEvent                      = "ContainerMetricsMdmHeartBeatEvent"
	PodReadyPercentageHeartBeatEvent                    = "PodReadyPercentageMdmHeartBeatEvent"
	ContainerResourceUtilHeartBeatEvent                 = "ContainerResourceUtilMdmHeartBeatEvent"
	PvUsageHeartBeatEvent                               = "PVUsageMdmHeartBeatEvent"
	PvKubeSystemMetricsEnabledEvent                     = "CollectPVKubeSystemMetricsEnabled"
	PvInventoryHeartBeatEvent                           = "KubePVInventoryHeartBeatEvent"
	TelemetryFlushIntervalInMinutes                     = 10
	KubeStateTelemetryFlushIntervalInMinutes            = 15
	ZeroFillMetricsIntervalInMinutes                    = 30
	MDMTimeSeriesFlushedInLastHour                      = "MdmTimeSeriesFlushedInLastHour"
	MDMExceptionTelemetryMetric                         = "AKSCustomMetricsMdmExceptions"
	MDMExceptionsMetricFlushInterval                    = 30
	// Pod Statuses
	PodStatusTerminating                                = "Terminating"

	AADMSIAuthMode                                      = "AAD_MSI_AUTH_MODE"
	MDM_EXCEPTIONS_METRIC_FLUSH_INTERVAL                = 30
	retryMDMPostWaitMinutes                             = 30
	metricsToCollect                                    = "cpuUsageNanoCores,memoryWorkingSetBytes,memoryRssBytes,pvUsedBytes"
	InsightsMetricsTagsPVCapacityBytes                  = "pvCapacityBytes"
)

// PvTypes is an array of strings representing different types of persistent volumes
var PvTypes = []string{"awsElasticBlockStore", "azureDisk", "azureFile", "cephfs", "cinder", "csi", "fc", "flexVolume", "flocker", "gcePersistentDisk", "glusterfs", "hostPath", "iscsi", "local", "nfs", "photonPersistentDisk", "portworxVolume", "quobyte", "rbd", "scaleIO", "storageos", "vsphereVolume"}
