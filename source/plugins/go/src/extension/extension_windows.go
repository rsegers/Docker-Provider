//go:build windows

package extension

import (
	"encoding/json"
	"fmt"

	winio "github.com/Microsoft/go-winio"
	uuid "github.com/google/uuid"
)

func (e *Extension) GetOutputNamedPipe(datatype string) string {
	extensionconfiglock.Lock()
	defer extensionconfiglock.Unlock()
	if len(e.datatypeStreamIdMap) > 0 && e.datatypeStreamIdMap[datatype] != "" {
		message := fmt.Sprintf("Windows AMA: OutputstreamId: %s for the datatype: %s", e.datatypeStreamIdMap[datatype], datatype)
		logger.Printf(message)
		return e.datatypeStreamIdMap[datatype]
	}
	var err error
	e.datatypeStreamIdMap, err = getDataTypeToNamedPipeMapping()
	if err != nil {
		message := fmt.Sprintf("Windows AMA: Error getting datatype to streamid mapping: %s", err.Error())
		logger.Printf(message)
	}
	return e.datatypeStreamIdMap[datatype]
}

func getExtensionConfigResponse(jsonBytes []byte) (string, error) {
	pipePath := `\\.\\pipe\\CAgentStream_CloudAgentInfo_AzureMonitorAgent`
	config_namedpipe, err := winio.DialPipe(pipePath, nil)
	if err != nil {
		logger.Printf("Windows AMA: error opening pipe: %v", err)
		return "", err
	}
	defer config_namedpipe.Close()
	number_bytes, err := config_namedpipe.Write(jsonBytes)
	if err != nil {
		logger.Printf("Windows AMA: write error: %v", err)
		return "", err
	}

	read_buffer := make([]byte, ReadBufferSize)
	number_bytes, err = config_namedpipe.Read(read_buffer)
	if err != nil {
		logger.Printf("Windows AMA: read error: %v", err)
		return "", err
	}
	read_buffer = read_buffer[:number_bytes]
	response := string(read_buffer)
	logger.Printf("extensionconfig::getExtensionConfigResponse:: getting extension config from fluent named pipe")

	return response, nil
}

func getDataTypeToNamedPipeMapping() (map[string]string, error) {

	guid := uuid.New()
	taggedData := map[string]interface{}{"Request": "AgentTaggedData", "RequestId": guid.String(), "Tag": "ContainerInsights", "Version": "1"}
	jsonBytes, err := json.Marshal(taggedData)
	response := getExtensionConfigResponse(jsonBytes)
	
	datatypeOutputStreamMap := make(map[string]string)

	var responseObjet AgentTaggedDataResponse
	err = json.Unmarshal([]byte(response), &responseObjet)
	if err != nil {
		logger.Printf("Error::Windows AMA:Failed to unmarshal config data. Error message: %s", string(err.Error()))
	}
	var extensionData TaggedData
	json.Unmarshal([]byte(responseObjet.TaggedData), &extensionData)

	extensionConfigs := extensionData.ExtensionConfigs
	outputStreamDefinitions := extensionData.OutputStreamDefinitions
	logger.Printf("Info::mdsd::build the datatype and streamid map -- start")
	for _, extensionConfig := range extensionConfigs {
		outputStreams := extensionConfig.OutputStreams
		for dataType, outputStreamID := range outputStreams {
			logger.Printf("Info::mdsd::datatype: %s, outputstreamId: %s", dataType, outputStreamID)
			datatypeOutputStreamMap[dataType] = outputStreamDefinitions[outputStreamID.(string)].NamedPipe
		}
	}
	logger.Printf("The data map CONTAINER_LOG_BLOB is -------------------------------------------------------")
	logger.Printf(datatypeOutputStreamMap["CONTAINER_LOG_BLOB"])
	logger.Printf("----------------------------------------------------------")
	return datatypeOutputStreamMap, nil

}
