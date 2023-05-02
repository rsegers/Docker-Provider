package extension

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"

	uuid "github.com/google/uuid"
	"github.com/ugorji/go/codec"
)

type Extension struct {
	datatypeStreamIdMap map[string]string
	dataCollectionSettings map[string]string
}

var singleton *Extension
var once sync.Once
var extensionconfiglock sync.Mutex
var logger *log.Logger
var containerType string

func GetInstance(flbLogger *log.Logger, containertype string) *Extension {
	once.Do(func() {
		singleton = &Extension{
			datatypeStreamIdMap:    make(map[string]string),
			dataCollectionSettings: make(map[string]string),
		}	
		flbLogger.Println("Extension Instance created")
	})
	logger = flbLogger
	containerType = containertype
	return singleton
}

func getExtensionConfigs() ([]ExtensionConfig, error) {
	logger.Printf("extensionconfig::getExtensionConfigs:: getting extension config from fluent socket - start")
	guid := uuid.New()
	
	taggedData := map[string]interface{}{"Request": "AgentTaggedData", "RequestId": guid.String(), "Tag": "ContainerInsights", "Version": "1"}
	jsonBytes, err := json.Marshal(taggedData)

	var data []byte
	enc := codec.NewEncoderBytes(&data, new(codec.MsgpackHandle))
	if err := enc.Encode(string(jsonBytes)); err != nil {
		return nil, err
	}

	fs := &FluentSocket{}
	fs.sockAddress = "/var/run/mdsd-ci/default_fluent.socket"
	if containerType != "" && strings.Compare(strings.ToLower(containerType), "prometheussidecar") == 0 {
		fs.sockAddress = fmt.Sprintf("/var/run/mdsd-%s/default_fluent.socket", containerType)
	}
	responseBytes, err := FluentSocketWriter.writeAndRead(fs, data)
	defer FluentSocketWriter.disconnect(fs)
	logger.Printf("Info::mdsd::Making call to FluentSocket: %s to write and read the config data", fs.sockAddress)
	if err != nil {
		return nil, err
	}
	response := string(responseBytes)

	var responseObject AgentTaggedDataResponse
	err = json.Unmarshal([]byte(response), &responseObject)
	if err != nil {
		logger.Printf("Error::mdsd::Failed to unmarshal config data. Error message: %s", string(err.Error()))
		return nil, err
	}

	var extensionData TaggedData
	json.Unmarshal([]byte(responseObject.TaggedData), &extensionData)
	logger.Printf("Info::mdsd::getExtensionConfigs:: getting extension config from fluent socket - end")

	return extensionData.ExtensionConfigs, nil
}

func getExtensionSettings() (map[string]map[string]interface{}, error) {
	logger.Printf("extensionconfig::getDataTypeToStreamIdMapping:: getting extension settings from ExtensionConfigs - start")
	extensionSettings := make(map[string]map[string]interface{})

	extensionConfigs, err := getExtensionConfigs()
	if err != nil {
		return extensionSettings, err
	}
	for _, extensionConfig := range extensionConfigs {
		extensionSettingsItr := extensionConfig.ExtensionSettings
		if extensionSettingsItr != nil && len(extensionSettingsItr) > 0 {
			extensionSettings = extensionSettingsItr
		}
	}
	logger.Printf("extensionconfig::getDataTypeToStreamIdMapping:: getting extension settings from ExtensionConfigs - end")

	return extensionSettings, nil
}

func getDataCollectionSettings() (map[string]string, error) {
	logger.Printf("extensionconfig::getDataTypeToStreamIdMapping:: getting datatype output stream map from fluent socket - start")
	dataCollectionSettings := make(map[string]string)

	extensionSettings, err := getExtensionSettings()
	if err != nil {
		return dataCollectionSettings, err
	}
	dataCollectionSettingsItr := extensionSettings["dataCollectionSettings"]
	if dataCollectionSettingsItr != nil && len(dataCollectionSettingsItr) > 0 {
		for k, v := range dataCollectionSettingsItr {
			dataCollectionSettings[k] = fmt.Sprintf("%v", v)
		}
	}
	logger.Printf("extensionconfig::getDataTypeToStreamIdMapping:: getting datatype output stream map from fluent socket - end")
	return dataCollectionSettings, nil
}

func getDataTypeToStreamIdMapping() (map[string]string, error) {
	logger.Printf("extensionconfig::getDataTypeToStreamIdMapping:: getting datatype output stream map from ExtensionConfigs - start")
	datatypeOutputStreamMap := make(map[string]string)

	extensionConfigs, err := getExtensionConfigs()
	if err != nil {
		return datatypeOutputStreamMap, err
	}

	logger.Printf("Info::mdsd::build the datatype and streamid map -- start")
	for _, extensionConfig := range extensionConfigs {
		outputStreams := extensionConfig.OutputStreams
		for dataType, outputStreamID := range outputStreams {
			logger.Printf("Info::mdsd::datatype: %s, outputstreamId: %s", dataType, outputStreamID)
			datatypeOutputStreamMap[dataType] = outputStreamID.(string)
		}
	}
	logger.Printf("Info::mdsd::build the datatype and streamid map -- end")
	logger.Printf("extensionconfig::getDataTypeToStreamIdMapping:: getting datatype output stream map from ExtensionConfigs - end")

	return datatypeOutputStreamMap, nil
}

func (e *Extension) IsContainerLogV2() bool {
	extensionconfiglock.Lock()
	defer extensionconfiglock.Unlock()
	if len(e.dataCollectionSettings) > 0 && e.dataCollectionSettings["isContainerLogV2"] != "" {
		message := fmt.Sprintf("isContainerLogV2: %s", e.dataCollectionSettings["isContainerLogV2"])
		logger.Printf(message)
		return e.dataCollectionSettings["isContainerLogV2"] == "true"
	}
	var err error
	e.dataCollectionSettings, err = getDataCollectionSettings()
	if err != nil {
		message := fmt.Sprintf("Error getting isContainerLogV2: %s", err.Error())
		logger.Printf(message)
	}
	return e.dataCollectionSettings["isContainerLogV2"] == "true"
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