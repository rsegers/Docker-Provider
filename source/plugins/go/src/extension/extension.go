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
		singleton = &Extension{make(map[string]string), make(map[string]string)}
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
	e.datatypeStreamIdMap, err = getExtensionDataTypeMapping(false)
	if err != nil {
		message := fmt.Sprintf("Error getting datatype to streamid mapping: %s", err.Error())
		logger.Printf(message)
	}
	return e.datatypeStreamIdMap[datatype]
}

func (e *Extension) GetOutputNamedPipe(datatype string) string {
	extensionconfiglock.Lock()
	defer extensionconfiglock.Unlock()
	if len(e.datatypeNamedPipeMap) > 0 && e.datatypeNamedPipeMap[datatype] != "" {
		message := fmt.Sprintf("Named Pipe: %s for the datatype: %s", e.datatypeNamedPipeMap[datatype], datatype)
		logger.Printf(message)
		return e.datatypeNamedPipeMap[datatype]
	}
	var err error
	e.datatypeNamedPipeMap, err = getExtensionDataTypeMapping(true)
	if err != nil {
		message := fmt.Sprintf("Error getting datatype to named pipe mapping: %s", err.Error())
		logger.Printf(message)
	}
	return e.datatypeNamedPipeMap[datatype]
}

func getExtensionDataTypeMapping(isNamedPipe bool) (map[string]string, error) {
	guid := uuid.New()
	datatypeMap := make(map[string]string)

	taggedData := map[string]interface{}{"Request": "AgentTaggedData", "RequestId": guid.String(), "Tag": "ContainerInsights", "Version": "1"}
	jsonBytes, err := json.Marshal(taggedData)
	// TODO: this error is unhandled

	response, err := getExtensionConfigResponse(jsonBytes)
	if err != nil {
		return datatypeMap, err
	}

	var responseObject AgentTaggedDataResponse
	err = json.Unmarshal([]byte(response), &responseObject)
	if err != nil {
		logger.Printf("Error::mdsd/Windows AMA::Failed to unmarshal config data. Error message: %s", string(err.Error()))
		return datatypeMap, err
	}

	var extensionData TaggedData
	json.Unmarshal([]byte(responseObject.TaggedData), &extensionData)

	extensionConfigs := extensionData.ExtensionConfigs
	outputStreamDefinitions := make(map[string]StreamDefinition)
	if isNamedPipe == true {
		outputStreamDefinitions = extensionData.OutputStreamDefinitions
	}
	logger.Printf("Info::mdsd/Windows AMA::build the datatype and streamid map -- start")
	for _, extensionConfig := range extensionConfigs {
		outputStreams := extensionConfig.OutputStreams
		for dataType, outputStreamID := range outputStreams {
			logger.Printf("Info::mdsd::datatype: %s, outputstreamId: %s", dataType, outputStreamID)
			if isNamedPipe {
				datatypeMap[dataType] = outputStreamDefinitions[outputStreamID.(string)].NamedPipe
			} else {
				datatypeMap[dataType] = outputStreamID.(string)
			}
		}
	}
	logger.Printf("Info::mdsd/Windows AMA::build the datatype and streamid map -- end")


	return datatypeMap, nil
}