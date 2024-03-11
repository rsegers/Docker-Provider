package mdm

import (
	"fmt"
)

type SeriesData struct {
	DimValues []string `json:"dimValues"`
	Min       float64  `json:"min"`
	Max       float64  `json:"max"`
	Sum       float64  `json:"sum"`
	Count     int      `json:"count"`
}

type BaseData struct {
	Metric    string       `json:"metric"`
	Namespace string       `json:"namespace"`
	DimNames  []string     `json:"dimNames"`
	Series    []SeriesData `json:"series"`
}

type GenericMetricTemplate struct {
	Time string `json:"time"`
	Data struct {
		BaseData BaseData `json:"baseData"`
	} `json:"data"`
}

// NewMetricTemplate creates a new metric template with the provided parameters.
func NewMetricTemplate(time, metric, namespace string, dimNames, dimValues []string, value float64) *GenericMetricTemplate {
	return &GenericMetricTemplate{
		Time: time,
		Data: struct {
			BaseData BaseData `json:"baseData"`
		}{
			BaseData: BaseData{
				Metric:    metric,
				Namespace: namespace,
				DimNames:  dimNames,
				Series: []SeriesData{
					{
						DimValues: dimValues,
						Min:       value,
						Max:       value,
						Sum:       value,
						Count:     1,
					},
				},
			},
		},
	}
}

// TODO: should sprintf below have precision limit?

func PodMetricsTemplate(time, metric string, dimValues []string, value float64) *GenericMetricTemplate {
	return NewMetricTemplate(time, metric, "insights.container/pods", []string{"controllerName", "Kubernetes namespace"}, dimValues, value)
}

func StableJobMetricsTemplate(time, metric string, dimValues []string, value float64) *GenericMetricTemplate {
	return NewMetricTemplate(time, metric, "insights.container/pods", []string{"controllerName", "Kubernetes namespace", "olderThanHours"}, dimValues, value)
}

func ContainerResourceUtilizationTemplate(time, metric, containerName, podName, controllerName, namespace string, thresholdPercentage float64, value float64) *GenericMetricTemplate {
	return NewMetricTemplate(time, metric, "insights.container/containers", []string{"containerName", "podName", "controllerName", "Kubernetes namespace", "thresholdPercentage"}, []string{containerName, podName, controllerName, namespace, fmt.Sprintf("%f", thresholdPercentage)}, value)
}

func ContainerResourceThresholdViolationTemplate(time, metric, containerName, podName, controllerName, namespace string, thresholdPercentage float64, value float64) *GenericMetricTemplate {
	return NewMetricTemplate(time, metric, "insights.container/containers", []string{"containerName", "podName", "controllerName", "Kubernetes namespace", "thresholdPercentage"}, []string{containerName, podName, controllerName, namespace, fmt.Sprintf("%f", thresholdPercentage)}, value)
}

func PVResourceUtilizationTemplate(time, metric, podName, computerName, namespace, volumeName string, thresholdPercentage float64, value float64) *GenericMetricTemplate {
	return NewMetricTemplate(time, metric, "insights.container/persistentvolumes", []string{"podName", "node", "kubernetesNamespace", "volumeName", "thresholdPercentage"}, []string{podName, computerName, namespace, volumeName, fmt.Sprintf("%f", thresholdPercentage)}, value)
}

func PVResourceThresholdViolationTemplate(time, metric, podName, computerName, namespace, volumeName string, thresholdPercentage float64, value float64) *GenericMetricTemplate {
	return NewMetricTemplate(time, metric, "insights.container/persistentvolumes", []string{"podName", "node", "kubernetesNamespace", "volumeName", "thresholdPercentage"}, []string{podName, computerName, namespace, volumeName, fmt.Sprintf("%f", thresholdPercentage)}, value)

}

func NodeResourceMetricsTemplate(time, metric string, hostValue string, value float64) *GenericMetricTemplate {
	return NewMetricTemplate(time, metric, "Insights.Container/nodes", []string{"host"}, []string{hostValue}, value)
}

func DiskUsedPercentageMetricsTemplate(time, metric, hostName, deviceName string, value float64) *GenericMetricTemplate {
	return NewMetricTemplate(time, metric, "Insights.Container/nodes", []string{"host", "device"}, []string{hostName, deviceName}, value)
}
