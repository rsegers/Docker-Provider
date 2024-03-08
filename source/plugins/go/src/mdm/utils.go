package mdm

import (
	"Docker-Provider/source/plugins/go/input/lib"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"math"
	"math/big"
	"os"
	"strconv"
	"strings"
)

// var logPath string
// var logger *log.Logger

// func init() {
// 	// osType := os.Getenv("OS_TYPE")
// 	// if osType != "" && strings.EqualFold(strings.TrimSpace(osType), "windows") {
// 	// 	logPath = "/etc/amalogswindows/filter_cadvisor2mdm.log"
// 	// } else {
// 	// 	logPath = "/var/opt/microsoft/docker-cimprov/log/filter_cadvisor2mdm.log"
// 	// }

// 	// file, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
// 	// if err != nil {
// 	// 	log.Fatalf("error opening log file: %v", err)
// 	// }
// 	// FLBLogger = lib.CreateLogger(logPath)

// 	// logger = log.New(file, "", log.LstdFlags)
// }

func CheckCustomMetricsAvailability() bool {
	aksRegion := os.Getenv("AKS_REGION")
	aksResourceID := os.Getenv("AKS_RESOURCE_ID")
	aksCloudEnvironment := os.Getenv("CLOUD_ENVIRONMENT")

	if aksRegion == "" || aksResourceID == "" {
		// This will also take care of AKS-Engine Scenario.
		// AKS_REGION/AKS_RESOURCE_ID is not set for AKS-Engine. Only ACS_RESOURCE_NAME is set
		return false
	}

	// If this is a cluster connected to ArcA control plane and metrics endpoint provided, custom metrics shall be emitted.
	isArcaCluster := os.Getenv("IS_ARCA_CLUSTER")
	customMetricsEndpoint := os.Getenv("CUSTOM_METRICS_ENDPOINT")

	if strings.ToLower(isArcaCluster) == "true" && customMetricsEndpoint != "" {
		return true
	}

	return strings.ToLower(aksCloudEnvironment) == "azurepubliccloud"
}

func GetNodeCapacity() (float64, float64, error) {
	cpuCapacity := 1.0
	memoryCapacity := 1.0

	response, err := lib.GetAllMetricsCAdvisor(nil)
	if err != nil {
		Log("MDMLog: Error get_node_capacity: %s", err)
		lib.SendExceptionTelemetry(err.Error(), nil)
		return cpuCapacity, memoryCapacity, err
	}
	defer response.Body.Close()

	body, err := ioutil.ReadAll(response.Body)
	if err != nil {
		Log("MDMLog: Error reading response body: %s", err)
		lib.SendExceptionTelemetry(err.Error(), nil)
		return cpuCapacity, memoryCapacity, err
	}

	allMetrics := strings.Split(string(body), "\n")
	for _, metric := range allMetrics {
		if strings.HasPrefix(metric, "machine_cpu_cores") {
			cpuValue := strings.Fields(metric)[1]
			cpuCapacity, err = strconv.ParseFloat(cpuValue, 64)
			if err != nil {
				Log("MDMLog: Error parsing CPU capacity: %s", err)
				lib.SendExceptionTelemetry(err.Error(), nil)
				return cpuCapacity, memoryCapacity, err
			}
			cpuCapacity *= 1000
			Log("MDMLog: CPU Capacity %f", cpuCapacity)
		}

		if strings.HasPrefix(metric, "machine_memory_bytes") {
			memoryValue := strings.Fields(metric)[1]
			memoryValueBig, ok := new(big.Float).SetString(memoryValue)
			if !ok {
				err := fmt.Errorf("invalid memory value: %s", memoryValue)
				Log("MDMLog: Error parsing Memory capacity: %s", err)
				lib.SendExceptionTelemetry(err.Error(), nil)
				return cpuCapacity, memoryCapacity, err
			}
			memoryCapacity, _ = memoryValueBig.Float64()
			Log("MDMLog: Memory Capacity %f", memoryCapacity)
		}
	}

	return cpuCapacity, memoryCapacity, nil
}

func GetNodeAllocatable(cpuCapacity, memoryCapacity float64) (float64, float64, error) {
	if cpuCapacity == 0.0 || memoryCapacity == 0.0 {
		Log("MDMLog: cpu_capacity or memory_capacity values not set. Hence we cannot calculate allocatable values")
		return 0.0, 0.0, errors.New("cpu_capacity or memory_capacity values not set")
	}

	cpuCapacityRounded, _ := big.NewFloat(cpuCapacity).SetPrec(2).Float64()
	memoryCapacityRounded, _ := big.NewFloat(memoryCapacity).SetPrec(2).Float64()

	cpuAllocatable := 1.0
	memoryAllocatable := 1.0

	allocatableResponse, err := lib.GetConfigzCAdvisor(nil)
	if err != nil {
		return 0.0, 0.0, err
	}

	defer allocatableResponse.Body.Close()

	var parsedResponse map[string]interface{}
	err = json.NewDecoder(allocatableResponse.Body).Decode(&parsedResponse)
	if err != nil {
		return 0.0, 0.0, err
	}

	kubereservedCPU, err := extractValue(parsedResponse, []string{"kubeletconfig", "kubeReserved", "cpu"}, "0.0")
	if err != nil {
		Log("MDMLog: %v", err)
		kubereservedCPU = "0.0"
	}

	kubereservedMemory, err := extractValue(parsedResponse, []string{"kubeletconfig", "kubeReserved", "memory"}, "0.0")
	if err != nil {
		Log("MDMLog: %v", err)
		kubereservedMemory = "0.0"
	}

	systemReservedCPU, err := extractValue(parsedResponse, []string{"kubeletconfig", "systemReserved", "cpu"}, "0.0")
	if err != nil {
		Log("MDMLog: %v", err)
		systemReservedCPU = "0.0"
	}

	explicitlyReservedCPU, err := extractValue(parsedResponse, []string{"kubeletconfig", "reservedCPUs"}, "0.0")
	if err != nil {
		Log("MDMLog: %v", err)
		explicitlyReservedCPU = "0.0"
	}

	systemReservedMemory, err := extractValue(parsedResponse, []string{"kubeletconfig", "systemReserved", "memory"}, "0.0")
	if err != nil {
		Log("MDMLog: %v", err)
		systemReservedMemory = "0.0"
	}

	evictionHardMemory, err := extractValue(parsedResponse, []string{"kubeletconfig", "evictionHard", "memory.available"}, "0.0")
	if err != nil {
		Log("MDMLog: %v", err)
		evictionHardMemory = "0.0"
	}

	cpuCapacityNumber := cpuCapacityRounded * 1000.0 * 1000.0
	if getMetricNumericValue("cpu", explicitlyReservedCPU) > 0 {
		cpuAllocatable = cpuCapacityNumber - getMetricNumericValue("cpu", explicitlyReservedCPU)
	} else {
		cpuAllocatable = cpuCapacityNumber - (getMetricNumericValue("cpu", kubereservedCPU) + getMetricNumericValue("cpu", systemReservedCPU))
	}
	cpuAllocatable /= 1000.0 * 1000.0

	memoryAllocatable = memoryCapacityRounded - (getMetricNumericValue("memory", kubereservedMemory) + getMetricNumericValue("memory", systemReservedMemory) + getMetricNumericValue("memory", evictionHardMemory))

	cpuAllocatableRounded, _ := big.NewFloat(cpuAllocatable).SetPrec(2).Float64()
	memoryAllocatableRounded, _ := big.NewFloat(memoryAllocatable).SetPrec(2).Float64()

	Log("MDMLog: CPU Allocatable %f", cpuAllocatableRounded)
	Log("MDMLog: Memory Allocatable %f", memoryAllocatableRounded)

	return cpuAllocatableRounded, memoryAllocatableRounded, nil
}

func extractValue(data map[string]interface{}, keys []string, defaultValue string) (string, error) {
	for _, key := range keys {
		if val, ok := data[key].(map[string]interface{}); ok {
			data = val
		} else {
			return defaultValue, nil
		}
	}
	if val, ok := data[keys[len(keys)-1]].(string); ok && val != "" {
		return val, nil
	}
	return defaultValue, nil
}

func getMetricNumericValue(metricName, metricVal string) float64 {
	metricValue := strings.ToLower(metricVal)

	switch metricName {
	case "memory":
		metricValue, err := convertMemoryMetric(metricValue, metricVal)
		if err != nil {
			Log("MDMLog: Error converting memory metric: %v", err)
			return 0
		}
		return metricValue

	case "cpu":
		metricValue, err := convertCPUMetric(metricValue)
		if err != nil {
			Log("MDMLog: Error converting CPU metric: %v", err)
			return 0
		}
		return metricValue

	case "nvidia.com/gpu", "amd.com/gpu":
		if value, err := convertToFloat(metricValue); err == nil {
			return value
		}

	default:
		Log("MDMLog: Unsupported metric %s. Returning 0 for metric value", metricName)
		return 0
	}

	return 0
}

func convertMemoryMetric(metricValue, originalMetricVal string) (float64, error) {
	switch {
	case strings.HasSuffix(metricValue, "ki"):
		return trimAndMultiply(metricValue, "ki", math.Pow(1024.0, 1)), nil
	case strings.HasSuffix(metricValue, "mi"):
		return trimAndMultiply(metricValue, "mi", math.Pow(1024.0, 2)), nil
	case strings.HasSuffix(metricValue, "gi"):
		return trimAndMultiply(metricValue, "gi", math.Pow(1024.0, 3)), nil
	case strings.HasSuffix(metricValue, "ti"):
		return trimAndMultiply(metricValue, "ti", math.Pow(1024.0, 4)), nil
	case strings.HasSuffix(metricValue, "pi"):
		return trimAndMultiply(metricValue, "pi", math.Pow(1024.0, 5)), nil
	case strings.HasSuffix(metricValue, "ei"):
		return trimAndMultiply(metricValue, "ei", math.Pow(1024.0, 6)), nil
	case strings.HasSuffix(metricValue, "zi"):
		return trimAndMultiply(metricValue, "zi", math.Pow(1024.0, 7)), nil
	case strings.HasSuffix(metricValue, "yi"):
		return trimAndMultiply(metricValue, "yi", math.Pow(1024.0, 8)), nil
	case strings.HasSuffix(metricValue, "k"):
		return trimAndMultiply(metricValue, "k", math.Pow(1000.0, 1)), nil
	case strings.HasSuffix(metricValue, "m"):
		metricValue = strings.TrimSuffix(metricValue, "m")
		val, _ := convertToFloat(metricValue)
		if strings.HasSuffix(originalMetricVal, "M") {
			val, _ := convertToFloat(metricValue)
			return val * math.Pow(1000.0, 2), nil
		}
		return val / 1000.0, nil
	case strings.HasSuffix(metricValue, "g"):
		return trimAndMultiply(metricValue, "g", math.Pow(1000.0, 3)), nil
	case strings.HasSuffix(metricValue, "t"):
		return trimAndMultiply(metricValue, "t", math.Pow(1000.0, 4)), nil
	case strings.HasSuffix(metricValue, "p"):
		return trimAndMultiply(metricValue, "p", math.Pow(1000.0, 5)), nil
	case strings.HasSuffix(metricValue, "e"):
		return trimAndMultiply(metricValue, "e", math.Pow(1000.0, 6)), nil
	case strings.HasSuffix(metricValue, "z"):
		return trimAndMultiply(metricValue, "z", math.Pow(1000.0, 7)), nil
	case strings.HasSuffix(metricValue, "y"):
		return trimAndMultiply(metricValue, "y", math.Pow(1000.0, 8)), nil
	default:
		return convertToFloat(metricValue)
	}
}

func convertCPUMetric(metricValue string) (float64, error) {
	switch {
	case strings.HasSuffix(metricValue, "m"):
		return trimAndMultiply(metricValue, "m", 1000.0*1000.0), nil
	case strings.HasSuffix(metricValue, "k"):
		return trimAndMultiply(metricValue, "k", 1000.0), nil
	default:
		defVal, err := convertToFloat(metricValue)
		if err != nil {
			Log("MDMLog: Error converting metric value: %v", err)
			return 0.0, err
		}
		return defVal * 1000.0 * 1000.0 * 1000.0, nil
	}
}

func trimAndMultiply(metricValue, suffix string, multiplier float64) float64 {
	value, err := convertToFloat(strings.TrimSuffix(metricValue, suffix))
	if err != nil {
		Log("MDMLog: Error converting metric value: %v", err)
		return 0
	}
	return value * multiplier
}

func convertToFloat(value string) (float64, error) {
	return strconv.ParseFloat(value, 64)
}

func GetAllContainerLimits() (map[string]float64, map[string]float64, map[string]string, error) {
	Log("MDMLog: in get_all_container_limits...")

	clusterID := lib.GetClusterID()
	containerCpuLimitHash := make(map[string]float64)
	containerMemoryLimitHash := make(map[string]float64)
	containerResourceDimensionHash := make(map[string]string)

	response, err := lib.GetPodsFromCAdvisor(nil)
	if err != nil {
		return nil, nil, nil, err
	}
	defer response.Body.Close()

	var podInventory struct {
		Items []struct {
			Metadata struct {
				Namespace       string `json:"namespace"`
				Name            string `json:"name"`
				OwnerReferences []struct {
					Name string `json:"name"`
				} `json:"ownerReferences"`
			} `json:"metadata"`
			Spec struct {
				Containers     []Container `json:"containers"`
				InitContainers []Container `json:"initContainers"`
			} `json:"spec"`
		} `json:"items"`
	}

	err = json.NewDecoder(response.Body).Decode(&podInventory)
	if err != nil {
		return nil, nil, nil, err
	}

	for _, item := range podInventory.Items {
		Log("MDMLog: in pod inventory items...")
		podNamespace := item.Metadata.Namespace
		podName := item.Metadata.Name
		podUid, err := getPodUid(podNamespace, map[string]interface{}{
			"namespace": podNamespace,
			"name":      podName,
		})
		if err != nil {
			Log("MDMLog: %v", err)
			continue
		}
		Log("MDMLog: podUid: %s", podUid)

		controllerName := "No Controller"
		if len(item.Metadata.OwnerReferences) > 0 && item.Metadata.OwnerReferences[0].Name != "" {
			controllerName = item.Metadata.OwnerReferences[0].Name
		}

		podContainers := append(item.Spec.Containers, item.Spec.InitContainers...)
		for _, container := range podContainers {
			Log("MDMLog: in podContainers for loop...")
			containerName := container.Name
			key := clusterID + "/" + podUid + "/" + containerName
			containerResourceDimensionHash[key] = containerName + "~~" + podName + "~~" + controllerName + "~~" + podNamespace

			if container.Resources.Limits.CPU != "" {
				cpuLimit := container.Resources.Limits.CPU
				memoryLimit := container.Resources.Limits.Memory
				Log("MDMLog: cpuLimit: %s", cpuLimit)
				Log("MDMLog: memoryLimit: %s", memoryLimit)

				containerCpuLimitHash[key] = getMetricNumericValue("cpu", cpuLimit)
				containerMemoryLimitHash[key] = getMetricNumericValue("memory", memoryLimit)
			}
		}
	}

	// Log("MDMLog: containerCpuLimitHash: %+v", containerCpuLimitHash)
	// Log("MDMLog: containerMemoryLimitHash: %+v", containerMemoryLimitHash)
	// Log("MDMLog: containerResourceDimensionHash: %+v", containerResourceDimensionHash)

	return containerCpuLimitHash, containerMemoryLimitHash, containerResourceDimensionHash, nil
}

type Container struct {
	Name      string `json:"name"`
	Resources struct {
		Limits struct {
			CPU    string `json:"cpu"`
			Memory string `json:"memory"`
		} `json:"limits"`
	} `json:"resources"`
}

func getPodUid(podNamespace string, podMetadata map[string]interface{}) (string, error) {
	var podUid string

	if podNamespace == "kube-system" {
		// Handle special case for kube-system namespace
		if _, ok := podMetadata["ownerReferences"]; !ok {
			annotations, ok := podMetadata["annotations"].(map[string]interface{})
			if !ok || annotations == nil {
				return "", nil // Returning empty string for nil UID
			}
			if hash, ok := annotations["kubernetes.io/config.hash"].(string); ok {
				podUid = hash
			}
		}
	} else {
		if uid, ok := podMetadata["uid"].(string); ok {
			podUid = uid
		}
	}

	if podUid == "" {
		Log("MDMLog: KubernetesApiClient::getPodUid: Failed to get podUid, podUid is empty.")
		// TODO: Add telemetry
		return "", nil // Returning empty string for nil UID
	}

	return podUid, nil
}

func ParseNodeLimits(metricJSON map[string]interface{}, metricCategory, metricNameToCollect, metricNametoReturn string, metricTime string) ([]map[string]interface{}, error) {
	var metricItems []map[string]interface{}

	if items, ok := metricJSON["items"].([]interface{}); ok {
		for _, item := range items {
			metricItem, err := ParseNodeLimitsFromNodeItem(item, metricCategory, metricNameToCollect, metricNametoReturn, metricTime)
			if err != nil {
				Log("MDMLog: Error parsing node limits from node item: %v", err)
				continue
			}
			if metricItem != nil {
				metricItems = append(metricItems, metricItem)
			}
		}
	} else {
		Log("MDMLog: Invalid format for 'items' in metricJSON")
		return nil, nil // or return an appropriate error
	}

	return metricItems, nil
}

func ParseNodeLimitsFromNodeItem(node interface{}, metricCategory, metricNameToCollect, metricNametoReturn, metricTime string) (map[string]interface{}, error) {
	var metricItem map[string]interface{}

	nodeMap, ok := node.(map[string]interface{})
	if !ok {
		Log("MDMLog: Error: Node is not a map")
		return nil, nil // Or return an appropriate error
	}

	clusterID := lib.GetClusterID()
	status, ok := nodeMap["status"].(map[string]interface{})
	if !ok {
		Log("MDMLog: Error: Status is not a map")
		return nil, nil // Or return an appropriate error
	}

	category, ok := status[metricCategory].(map[string]interface{})
	if !ok {
		Log("MDMLog: Error: %s is not a map", metricCategory)
		return nil, nil // Or return an appropriate error
	}

	metricVal, ok := category[metricNameToCollect]
	if !ok {
		Log("MDMLog: Error: %s not found in %s", metricNameToCollect, metricCategory)
		return nil, nil // Or return an appropriate error
	}

	metricValue := getMetricNumericValue(metricNameToCollect, metricVal.(string))

	metadata, ok := nodeMap["metadata"].(map[string]interface{})
	if !ok {
		Log("MDMLog: Error: Metadata is not a map")
		return nil, nil // Or return an appropriate error
	}

	host, ok := metadata["name"].(string)
	if !ok {
		Log("MDMLog: Error: Name is not a string in metadata")
		return nil, nil // Or return an appropriate error
	}

	metricItem = make(map[string]interface{})
	metricItem["Timestamp"] = metricTime
	metricItem["Host"] = host
	metricItem["Computer"] = host
	metricItem["ObjectName"] = "K8SNode"
	metricItem["InstanceName"] = clusterID + "/" + host

	metricCollection := map[string]interface{}{
		"CounterName": metricNametoReturn,
		"Value":       metricValue,
	}
	metricCollections := []interface{}{metricCollection}

	metricCollectionsJSON, err := json.Marshal(metricCollections)
	if err != nil {
		Log("MDMLog: Error marshalling metricCollections: %v", err)
		return nil, nil // Or return an appropriate error
	}

	metricItem["json_Collections"] = string(metricCollectionsJSON)

	return metricItem, nil
}

// func ConvertMap(inputMap map[interface{}]interface{}) map[string]string {
// 	outputMap := make(map[string]string)
// 	for key, value := range inputMap {
// 		// Convert key to string
// 		strKey, ok := key.(string)
// 		if !ok {
// 			continue // or handle the error as appropriate
// 		}

// 		// Use type assertion to convert value to string
// 		switch v := value.(type) {
// 		case string:
// 			outputMap[strKey] = v
// 		case []uint8:
// 			// Convert byte slice to string
// 			outputMap[strKey] = string(v)
// 		case int:
// 			outputMap[strKey] = strconv.Itoa(v)
// 		case float64:
// 			outputMap[strKey] = strconv.FormatFloat(v, 'f', 2, 64)
// 		case bool:
// 			outputMap[strKey] = strconv.FormatBool(v)
// 		default:
// 			outputMap[strKey] = fmt.Sprintf("%v", v)
// 		}
// 	}
// 	return outputMap
// }
