package main

import (
	"encoding/json"
	"testing"
	"github.com/stretchr/testify/assert"
	"fmt"
)

var kubernetesJSON = `{
	"pod_name":"test-publisher-ds-bssg6",
	"namespace_name":"kube-system",
	"pod_id":"93bf47d2-5c1a-42bc-test-481939a93a66",
	"labels":{
		"app":"test",
		"controller-revision-hash":"f48799794",
		"dsName":"defender-publisher-ds",
		"kubernetes.azure.com/managedby":"aks",
		"pod-template-generation":"2"
	},
	"annotations":{
		"kubernetes.io/config.seen":"2023-10-02T08:21:49.954540360Z",
		"kubernetes.io/config.source":"api"
	},
	"host":"test-agentpool-test-test000001",
	"container_name":"test-publisher",
	"docker_id":"test1234567890123213213123213213213213",
	"container_hash":publisher@sha256:test1234567890123213213123213213213213",
	"container_image":"test-publisher:1.0.67"
}`

func toInterfaceMap(m map[string]interface{}) map[interface{}]interface{} {
	result := make(map[interface{}]interface{})
	for k, v := range m {
		result[k] = v
	}
	return result
}

// Test PostDataHelper KuberneteMetadata
func TestPostDataHelperKuberneteMetadata(t *testing.T) {
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