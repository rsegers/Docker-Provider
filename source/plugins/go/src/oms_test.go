package main

import (
	"encoding/json"
	"testing"
	"github.com/stretchr/testify/assert"
	"fmt"
)

var kubernetesJSON = `{
	"pod_name":"microsoft-defender-publisher-ds-bssg6",
	"namespace_name":"kube-system",
	"pod_id":"93bf47d2-5c1a-42bc-9a22-481939a93a66",
	"labels":{
		"app":"defender",
		"controller-revision-hash":"f48799794",
		"dsName":"microsoft-defender-publisher-ds",
		"kubernetes.azure.com/managedby":"aks",
		"pod-template-generation":"2"
	},
	"annotations":{
		"kubernetes.io/config.seen":"2023-10-02T08:21:49.954540360Z",
		"kubernetes.io/config.source":"api"
	},
	"host":"aks-agentpool-15410898-vmss000001",
	"container_name":"microsoft-defender-publisher",
	"docker_id":"c695de72af6b3f5a6ed9770813f3235c20225ca344172335e030abc8431a1216",
	"container_hash":"mcr.microsoft.com/azuredefender/stable/security-publisher@sha256:f64bbdbd552c18dcd6455508ba7282ee03cf86de5dbfbca665e9573f29218d69",
	"container_image":"mcr.microsoft.com/azuredefender/stable/security-publisher:1.0.67"
}`

func toInterfaceMap(m map[string]interface{}) map[interface{}]interface{} {
	result := make(map[interface{}]interface{})
	for k, v := range m {
		result[k] = v
	}
	return result
}

// Test PostDataHelper
func TestPostDataHelper(t *testing.T) {
	var intermediateMap map[string]interface{}
    // Unmarshal JSON data into a map
    err := json.Unmarshal([]byte(kubernetesJSON), &intermediateMap)
    if err != nil {
        fmt.Println("Error unmarshalling JSON:", err)
        return
    }
	kubernetesMetadata := toInterfaceMap(intermediateMap)

	record := map[interface{}]interface{}{
		"filepath": "/var/log/containers/pod_xyz.log",
		"stream": "stdout",
		"kubernetes": kubernetesMetadata,
	}
	
	KubernetesMetadataIncludeList = []string{
		"podlabels", "podannotations", "poduid", "image", "imageid", "imagerepo", "imagetag",
	}
	KubernetesMetadataEnabled = true

	output := PostDataHelper([]map[interface{}]interface{}{record})

	assert.Greater(t, output, 0, "Expected output to be greater than 0 indicating processing occurred")
}