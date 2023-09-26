package lib

import (
	"encoding/json"
	"testing"
	"io/ioutil"
)

func Test_GetMetricsHelper(t *testing.T) {
	summaryStatsInfo := map[string]interface{}{}
	jsonData, err := ioutil.ReadFile("testdata/summary1.json")
	if err != nil {
		t.Fatalf("Failed to read data.json file: %v", err)
	}
	err = json.Unmarshal(jsonData, &summaryStatsInfo)
	if err != nil {
		t.Fatalf("Failed to read summary.json file: %v", err)
	}

	dataItems1 := GetMetricsHelper(summaryStatsInfo, nil, "", nil, "")
	if dataItems1 == nil {
		t.Fatalf("Failed to get dataItems")
	}

	jsonData, err = ioutil.ReadFile("testdata/summary2.json")
	if err != nil {
		t.Fatalf("Failed to read data.json file: %v", err)
	}
	err = json.Unmarshal(jsonData, &summaryStatsInfo)
	if err != nil {
		t.Fatalf("Failed to read summary.json file: %v", err)
	}
	dataItems2 := GetMetricsHelper(summaryStatsInfo, nil, "", nil, "")
	if dataItems2 == nil {
		t.Fatalf("Failed to get dataItems")
	}
}