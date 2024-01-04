package main

import (
	"os"
	"strings"
)

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
