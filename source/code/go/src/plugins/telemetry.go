package main

import (
	"encoding/base64"
	"errors"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/Microsoft/ApplicationInsights-Go/appinsights"
)

var (
	// FlushedRecordsCount indicates the number of flushed records in the current period
	FlushedRecordsCount float64
	// FlushedRecordsTimeTaken indicates the cumulative time taken to flush the records for the current period
	FlushedRecordsTimeTaken float64
	// CommonProperties indicates the dimensions that are sent with every event/metric
	CommonProperties map[string]string
	// TelemetryClient is the client used to send the telemetry
	TelemetryClient appinsights.TelemetryClient
	// ContainerLogTelemetryTicker sends telemetry periodically
	ContainerLogTelemetryTicker *time.Ticker
)

const (
	clusterTypeACS               = "ACS"
	clusterTypeAKS               = "AKS"
	controllerTypeDaemonSet      = "DaemonSet"
	controllerTypeReplicaSet     = "ReplicaSet"
	envAKSResourceID             = "AKS_RESOURCE_ID"
	envACSResourceName           = "ACS_RESOURCE_NAME"
	envAppInsightsAuth           = "APPLICATIONINSIGHTS_AUTH"
	metricNameAvgFlushRate       = "ContainerLogAvgRecordsFlushedPerSec"
	defaultTelemetryPushInterval = 300

	// EventNameContainerLogInit name of the event
	EventNameContainerLogInit = "ContainerLogPluginInitialized"
)

// Initialize initializes the telemetry artifacts
func initialize(telemetryPushIntervalProperty string, agentVersion string) (int, error) {

	telemetryPushInterval, err := strconv.Atoi(telemetryPushIntervalProperty)
	if err != nil {
		Log("Error Converting telemetryPushIntervalProperty %s. Using Default Interval... %d \n", telemetryPushIntervalProperty, defaultTelemetryPushInterval)
		telemetryPushInterval = defaultTelemetryPushInterval
	}

	ContainerLogTelemetryTicker = time.NewTicker(time.Second * time.Duration(telemetryPushInterval))

	encodedIkey := os.Getenv(envAppInsightsAuth)
	if encodedIkey == "" {
		Log("Environment Variable Missing \n")
		return -1, errors.New("Missing Environment Variable")
	}

	decIkey, err := base64.StdEncoding.DecodeString(encodedIkey)
	if err != nil {
		Log("Decoding Error %s", err.Error())
		return -1, err
	}

	TelemetryClient = appinsights.NewTelemetryClient(string(decIkey))

	CommonProperties = make(map[string]string)
	CommonProperties["Computer"] = Computer
	CommonProperties["WorkspaceID"] = WorkspaceID
	CommonProperties["ControllerType"] = controllerTypeDaemonSet
	CommonProperties["AgentVersion"] = agentVersion

	aksResourceID := os.Getenv(envAKSResourceID)
	// if the aks resource id is not defined, it is most likely an ACS Cluster
	if aksResourceID == "" {
		CommonProperties["ACSResourceName"] = os.Getenv(envACSResourceName)
		CommonProperties["ClusterType"] = clusterTypeACS

		CommonProperties["SubscriptionID"] = ""
		CommonProperties["ResourceGroupName"] = ""
		CommonProperties["ClusterName"] = ""
		CommonProperties["Region"] = ""

	} else {
		CommonProperties["ACSResourceName"] = ""
		splitStrings := strings.Split(aksResourceID, "/")
		CommonProperties["SubscriptionID"] = splitStrings[2]
		CommonProperties["ResourceGroupName"] = splitStrings[4]
		CommonProperties["ClusterName"] = splitStrings[8]
		CommonProperties["ClusterType"] = clusterTypeAKS

		region := os.Getenv("AKS_REGION")
		if region != "" {
			CommonProperties["Region"] = region
		}
	}

	TelemetryClient.Context().CommonProperties = CommonProperties
	return 0, nil
}

// SendContainerLogFlushRateMetric is a go-routine that flushes the data periodically (every 5 mins to App Insights)
func SendContainerLogFlushRateMetric(telemetryPushIntervalProperty string, agentVersion string) {

	ret, err := initialize(telemetryPushIntervalProperty, agentVersion)
	if ret != 0 || err != nil {
		Log("Error During Telemetry Initialization :%s", err.Error())
		runtime.Goexit()
	}

	SendEvent(EventNameContainerLogInit, make(map[string]string))

	for ; true; <-ContainerLogTelemetryTicker.C {
		flushRate := FlushedRecordsCount / FlushedRecordsTimeTaken * 1000
		metric := appinsights.NewMetricTelemetry(metricNameAvgFlushRate, flushRate)
		Log("Flushed Records : %f Time Taken : %f flush Rate : %f", FlushedRecordsCount, FlushedRecordsTimeTaken, flushRate)
		TelemetryClient.Track(metric)
		FlushedRecordsCount = 0.0
		FlushedRecordsTimeTaken = 0.0
	}
}

// TelemetryShutdown stops the ticker that sends data to App Insights periodically
func TelemetryShutdown() {
	Log("Shutting down ContainerLog Telemetry\n")
	ContainerLogTelemetryTicker.Stop()
}

// SendEvent sends an event to App Insights
func SendEvent(eventName string, dimensions map[string]string) {
	// this is because the TelemetryClient is initialized in a different goroutine. A simple wait loop here is just waiting for it to be initialized. This will happen only for the init event. Any subsequent Event should work just fine
	for TelemetryClient == nil {
		Log("Waiting for Telemetry Client to be initialized")
		time.Sleep(1 * time.Second)
	}

	// take a copy so the CommonProperties can be restored later
	_commonProps := make(map[string]string)
	for k, v := range TelemetryClient.Context().CommonProperties {
		_commonProps[k] = v
	}

	// add any extra dimensions
	for k, v := range dimensions {
		TelemetryClient.Context().CommonProperties[k] = v
	}

	Log("Sending Event : %s\n", eventName)
	event := appinsights.NewEventTelemetry(eventName)
	TelemetryClient.Track(event)

	// restore original CommonProperties
	TelemetryClient.Context().CommonProperties = _commonProps
}
