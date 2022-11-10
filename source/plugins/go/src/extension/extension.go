package extension

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"

	uuid "github.com/google/uuid"
)

type Extension struct {
	datatypeStreamIdMap map[string]string
	datatypeNamedPipeMap map[string]string
}

var singleton *Extension
var once sync.Once
var extensionconfiglock sync.Mutex
var logger *log.Logger
var containerType string

func GetInstance(flbLogger *log.Logger, containertype string) *Extension {
	once.Do(func() {
		singleton = &Extension{make(map[string]string)}
		flbLogger.Println("Extension Instance created")
	})
	logger = flbLogger
	containerType = containertype
	return singleton
}

func (e *Extension) GetOutputStreamId(datatype string) string {
	extensionconfiglock.Lock()
	defer extensionconfiglock.Unlock()
	if len(e.datatypeStreamIdMap) > 0 && e.datatypeStreamIdMap[datatype] != "" {
		message := fmt.Sprintf("OutputstreamId: %s for the datatype: %s", e.datatypeStreamIdMap[datatype], datatype)
		logger.Printf(message)
		return e.datatypeStreamIdMap[datatype]
	}
	var err error
	e.datatypeStreamIdMap, err = getDataTypeToStreamIdMapping()
	if err != nil {
		message := fmt.Sprintf("Error getting datatype to streamid mapping: %s", err.Error())
		logger.Printf(message)
	}
	return e.datatypeStreamIdMap[datatype]
}

func getDataTypeToStreamIdMapping() (map[string]string, error) {
	logger.Printf("extensionconfig::getDataTypeToStreamIdMapping:: getting extension config from fluent socket - start")
	guid := uuid.New()
	datatypeOutputStreamMap := make(map[string]string)

	taggedData := map[string]interface{}{"Request": "AgentTaggedData", "RequestId": guid.String(), "Tag": "ContainerInsights", "Version": "1"}
	jsonBytes, err := json.Marshal(taggedData)
	// TODO: this error is unhandled

	response, err := getExtensionConfigResponse(jsonBytes)
	if err != nil {
		return datatypeOutputStreamMap, err
	}

	var responseObject AgentTaggedDataResponse
	err = json.Unmarshal([]byte(response), &responseObject)
	if err != nil {
		logger.Printf("Error::mdsd::Failed to unmarshal config data. Error message: %s", string(err.Error()))
		return datatypeOutputStreamMap, err
	}

	var extensionData TaggedData
	json.Unmarshal([]byte(responseObject.TaggedData), &extensionData)

	extensionConfigs := extensionData.ExtensionConfigs
	logger.Printf("Info::mdsd::build the datatype and streamid map -- start")
	for _, extensionConfig := range extensionConfigs {
		outputStreams := extensionConfig.OutputStreams
		for dataType, outputStreamID := range outputStreams {
			logger.Printf("Info::mdsd::datatype: %s, outputstreamId: %s", dataType, outputStreamID)
			datatypeOutputStreamMap[dataType] = outputStreamID.(string)
		}
	}
	logger.Printf("Info::mdsd::build the datatype and streamid map -- end")


	return datatypeOutputStreamMap, nil
}
