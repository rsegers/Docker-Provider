package mdm

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"
)

var (
	OsType                       string
	LogPath                      string
	Logger                       *log.Logger
	HostName                     string
	OomKilledContainerCountHash  map[string]int
	ContainerRestartCountHash    map[string]int
	StaleJobCountHash            map[string]int
	PodReadyHash                 map[string]int
	PodNotReadyHash              map[string]int
	PodReadyPercentageHash       map[string]float64
	SendZeroFilledMetrics        bool
	ZeroFilledMetricsTimeTracker time.Time

	ZeroFillMetricsHash = map[string]bool{
		MDMOOMKilledContainerCount: true,
		MDMContainerRestartCount:   true,
		MDMStaleCompletedJobCount:  true,
	}
	NodeMetricNameMetricPercentageNameHash = map[string]string{
		CPUUsageMilliCores:    MDMNodeCpuUsagePercentage,
		MemoryRssBytes:        MDMNodeMemoryRssPercentage,
		MemoryWorkingSetBytes: MDMNodeMemoryWorkingSetPercentage,
	}

	NodeMetricNameMetricAllocatablePercentageNameHash = map[string]string{
		CPUUsageMilliCores:    MDMNodeCpuUsageAllocatablePercentage,
		MemoryRssBytes:        MDMNodeMemoryRssAllocatablePercentage,
		MemoryWorkingSetBytes: MDMNodeMemoryWorkingSetAllocatablePercentage,
	}

	ContainerMetricNameMetricPercentageNameHash = map[string]string{
		CPUUsageMilliCores:    MDMContainerCpuUtilizationMetric,
		CPUUsageNanoCores:     MDMContainerCpuUtilizationMetric,
		MemoryRssBytes:        MDMContainerMemoryRssUtilizationMetric,
		MemoryWorkingSetBytes: MDMContainerMemoryWorkingSetUtilizationMetric,
	}

	ContainerMetricNameMetricThresholdViolatedHash = map[string]string{
		CPUUsageMilliCores:    MDMContainerCpuThresholdViolatedMetric,
		CPUUsageNanoCores:     MDMContainerCpuThresholdViolatedMetric,
		MemoryRssBytes:        MDMContainerMemoryRssThresholdViolatedMetric,
		MemoryWorkingSetBytes: MDMContainerMemoryWorkingSetThresholdViolatedMetric,
	}

	PodMetricNameMetricPercentageNameHash = map[string]string{
		PVUsedBytes: MDMPvUtilizationMetric,
	}

	PodMetricNameMetricThresholdViolatedHash = map[string]string{
		PVUsedBytes: MDMPvThresholdViolatedMetric,
	}
)

func init() {
	// Setup log path based on OS type
	OsType = os.Getenv("OS_TYPE")
	if strings.EqualFold(OsType, "windows") {
		LogPath = "/etc/amalogswindows/mdm_metrics_generator.log"
	} else {
		LogPath = "/var/opt/microsoft/docker-cimprov/log/mdm_metrics_generator.log"
	}

	isTestEnv := os.Getenv("ISTEST") == "true"
	if isTestEnv {
		LogPath = "./mdm_metrics_generator.log"
	}

	// Initialize Logger
	logFile, err := os.OpenFile(LogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}
	Logger = log.New(logFile, "INFO: ", log.Ldate|log.Ltime|log.Lshortfile)
}

func GetDiskUsageMetricRecords(record map[string]interface{}) ([]*GenericMetricTemplate, error) {
	var metricRecords []*GenericMetricTemplate
	var tags map[string]interface{}
	tagMap := make(map[string]string)

	if record["tags"] == nil {
		Log.Printf("translateTelegrafMetrics: tags are missing in the metric record")
		return metricRecords, nil
	} else {
		tags = record["tags"].(map[string]interface{})
		for k, v := range tags {
			key := fmt.Sprintf("%s", k)
			if key == "" {
				continue
			}
			tagMap[key] = fmt.Sprintf("%s", v)
		}
	}
	fieldMap := record["fields"].(map[string]interface{})
	usedPercent, hasUsedPercent := fieldMap["used_percent"].(float64)
	deviceName, hasDeviceName := tagMap["device"]
	hostName, hasHostName := tagMap["hostName"]

	if hasUsedPercent && hasDeviceName && hasHostName {
		timestamp := time.Unix(int64(record["timestamp"].(uint64)), 0).UTC().Format(time.RFC3339)
		diskUsagePercentageRecord := DiskUsedPercentageMetricsTemplate(timestamp, MDMDiskUsedPercentage, hostName, deviceName, usedPercent)
		metricRecords = append(metricRecords, diskUsagePercentageRecord)
	}
	return metricRecords, nil
}

func GetMetricRecords(record map[string]interface{}) ([]*GenericMetricTemplate, error) {
	var metricRecords []*GenericMetricTemplate
	var tags map[string]interface{}
	tagMap := make(map[string]string)

	if record["tags"] == nil {
		Log.Printf("translateTelegrafMetrics: tags are missing in the metric record")
		return metricRecords, nil
	} else {
		tags = record["tags"].(map[string]interface{})
		for k, v := range tags {
			key := fmt.Sprintf("%s", k)
			if key == "" {
				continue
			}
			tagMap[key] = fmt.Sprintf("%s", v)
		}
	}

	const maxDim = 10
	var dimNames, dimValues []string
	for k, v := range tagMap {
		if len(dimNames) < maxDim {
			dimNames = append(dimNames, fmt.Sprintf("\"%s\"", k))
			if v != "" {
				dimValues = append(dimValues, fmt.Sprintf("\"%s\"", v))
			} else {
				dimValues = append(dimValues, "\"-\"") // Assuming "-" is used for empty values
			}
		}
	}

	fieldMap := record["fields"].(map[string]interface{})

	convertedTimestamp := time.Unix(int64(record["timestamp"].(int64)), 0).UTC().Format(time.RFC3339)
	for k, v := range fieldMap {
		if isNumeric(v) {
			metricValue, _ := v.(float64)
			m := NewMetricTemplate(convertedTimestamp, k, record["name"].(string), dimNames, dimValues, metricValue)
			metricRecords = append(metricRecords, m)
		}
	}
	return metricRecords, nil
}

func GetContainerResourceUtilizationThresholds() map[string]float64 {
	metricThresholdHash := map[string]float64{
		CPUUsageNanoCores:     DefaultMDMCpuUtilizationThreshold,
		MemoryRssBytes:        DefaultMDMMemoryRssThreshold,
		MemoryWorkingSetBytes: DefaultMDMMemoryWorkingSetThreshold,
		PVUsedBytes:           DefaultMDMPvUtilizationThreshold,
		JobCompletionTime:     float64(DefaultMDMJobCompletedTimeThresholdMinutes),
	}

	if cpuThreshold, err := getEnvFloat("AZMON_ALERT_CONTAINER_CPU_THRESHOLD"); err == nil {
		metricThresholdHash[CPUUsageNanoCores] = cpuThreshold
	}
	if memoryRssThreshold, err := getEnvFloat("AZMON_ALERT_CONTAINER_MEMORY_RSS_THRESHOLD"); err == nil {
		metricThresholdHash[MemoryRssBytes] = memoryRssThreshold
	}
	if memoryWorkingSetThreshold, err := getEnvFloat("AZMON_ALERT_CONTAINER_MEMORY_WORKING_SET_THRESHOLD"); err == nil {
		metricThresholdHash[MemoryWorkingSetBytes] = memoryWorkingSetThreshold
	}
	if pvUsagePercentageThreshold, err := getEnvFloat("AZMON_ALERT_PV_USAGE_THRESHOLD"); err == nil {
		metricThresholdHash[PVUsedBytes] = pvUsagePercentageThreshold
	}
	if jobCompletionTimeThreshold, err := getEnvInt("AZMON_ALERT_JOB_COMPLETION_TIME_THRESHOLD"); err == nil {
		metricThresholdHash[JobCompletionTime] = float64(jobCompletionTimeThreshold)
	}

	return metricThresholdHash
}

func getEnvFloat(key string) (float64, error) {
	val, exists := os.LookupEnv(key)
	if !exists {
		return 0, fmt.Errorf("environment variable %s not found", key)
	}
	return strconv.ParseFloat(val, 64)
}

func getEnvInt(key string) (int, error) {
	val, exists := os.LookupEnv(key)
	if !exists {
		return 0, fmt.Errorf("environment variable %s not found", key)
	}
	return strconv.Atoi(val)
}

func GetNodeResourceMetricRecords(record map[string]interface{}, metricName string, metricValue float64, percentageMetricValue float64, allocatablePercentageMetricValue float64) ([]*GenericMetricTemplate, error) {
	var metricRecords []*GenericMetricTemplate
	custommetricrecord := NodeResourceMetricsTemplate(record["Timestamp"].(string), metricName, record["Host"].(string), metricValue)
	metricRecords = append(metricRecords, custommetricrecord)

	additionalRecord := NodeResourceMetricsTemplate(record["Timestamp"].(string), NodeMetricNameMetricPercentageNameHash[metricName], record["Host"].(string), percentageMetricValue)
	metricRecords = append(metricRecords, additionalRecord)

	additionalRecord = NodeResourceMetricsTemplate(record["Timestamp"].(string), NodeMetricNameMetricAllocatablePercentageNameHash[metricName], record["Host"].(string), allocatablePercentageMetricValue)
	metricRecords = append(metricRecords, additionalRecord)

	return metricRecords, nil
}

func GetContainerResourceUtilMetricRecords(recordTimeStamp string, metricName string, percentageMetricValue float64, dims string, thresholdPercentage float64, isZeroFill bool) ([]*GenericMetricTemplate, error) {
	var records []*GenericMetricTemplate
	if dims == "" {
		Log.Printf("Dimensions nil, returning empty records")
		return records, nil
	}

	dimElements := strings.Split(dims, "~~")
	if len(dimElements) != 4 {
		return records, nil
	}

	// Get dimension values
	containerName := dimElements[0]
	podName := dimElements[1]
	controllerName := dimElements[2]
	podNamespace := dimElements[3]

	resourceUtilRecord := ContainerResourceUtilizationTemplate(recordTimeStamp, metricName, containerName, podName, controllerName, podNamespace, thresholdPercentage, percentageMetricValue)
	records = append(records, resourceUtilRecord)

	var containerResourceThresholdViolated int
	if isZeroFill {
		containerResourceThresholdViolated = 0
	} else {
		containerResourceThresholdViolated = 1
	}
	resourceThresholdViolatedRecord := ContainerResourceThresholdViolationTemplate(recordTimeStamp, ContainerMetricNameMetricThresholdViolatedHash[metricName], containerName, podName, controllerName, podNamespace, thresholdPercentage, float64(containerResourceThresholdViolated))
	records = append(records, resourceThresholdViolatedRecord)

	return records, nil

}

func GetPVResourceUtilMetricRecords(recordTimeStamp string, metricName string, computer string, percentageMetricValue float64, dims map[string]string, thresholdPercentage float64, isZeroFill bool) ([]*GenericMetricTemplate, error) {
	var records []*GenericMetricTemplate
	pvcNamespace := dims["pvcNamespace"]
	podName := dims["podName"]
	volumeName := dims["volumeName"]

	resourceUtilRecord := PVResourceUtilizationTemplate(recordTimeStamp, PodMetricNameMetricPercentageNameHash[metricName], podName, computer, pvcNamespace, volumeName, thresholdPercentage, percentageMetricValue)
	records = append(records, resourceUtilRecord)

	var pvResourceThresholdViolated int
	if isZeroFill {
		pvResourceThresholdViolated = 0
	} else {
		pvResourceThresholdViolated = 1
	}

	resourceThresholdViolatedRecord := PVResourceThresholdViolationTemplate(recordTimeStamp, PodMetricNameMetricThresholdViolatedHash[metricName], podName, computer, pvcNamespace, volumeName, thresholdPercentage, float64(pvResourceThresholdViolated))

	records = append(records, resourceThresholdViolatedRecord)

	return records, nil
}

func isNumeric(o interface{}) bool {
	switch v := o.(type) {
	case float64, float32, int, int8, int16, int32, int64, uint, uint8, uint16, uint32, uint64:
		// If it's already a numeric type, no need to parse
		return true
	case string:
		// Try to parse the string as a float
		_, err := strconv.ParseFloat(v, 64)
		return err == nil
	default:
		// Not a numeric type
		return false
	}
}
