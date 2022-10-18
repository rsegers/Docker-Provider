// +build windows

package extension_windows

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"

	"github.com/Microsoft/go-winio"
	uuid "github.com/google/uuid"
	"github.com/ugorji/go/codec"
)

type Extension_Windows struct {
	datatypeStreamIdMap map[string]string
}

var singleton *Extension_Windows
var once sync.Once
var extensionconfiglock sync.Mutex
var logger *log.Logger
var containerType string

func GetInstance(flbLogger *log.Logger, containertype string) *Extension_Windows {
	once.Do(func() {
		singleton = &Extension_Windows{make(map[string]string)}
		flbLogger.Println("Extension_Windows Instance created")
	})
	logger = flbLogger
	containerType = containertype
	return singleton
}

func (e *Extension_Windows) GetOutputNamedPipe(datatype string) string {
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

func getDataTypeToNamedPipeMapping() (map[string]string, error) {
	logger.Printf("extensionconfig::getDataTypeToNamedPipeMapping:: getting extension config from named pipe - start")
	pipePath := `\\.\\pipe\\CAgentStream_CloudAgentInfo_AzureMonitorAgent`
	f, err := winio.DialPipe(pipePath, nil)
	if err != nil {
		logger.Printf("Windows AMA: error opening pipe: %v", err)
	}
	defer f.Close()

	guid := uuid.New()
	taggedData := map[string]interface{}{"Request": "AgentTaggedData", "RequestId": guid.String(), "Tag": "ContainerInsights", "Version": "1"}
	jsonBytes, err := json.Marshal(taggedData)

	n, err := f.Write([]byte(jsonBytes))
	if err != nil {
		logger.Printf("write error: %v", err)
	}
	logger.Printf("Windows AMA: wrote:", n)

	buf := make([]byte, 262144)
	n, err = f.Read(buf)
	if err != nil {
		log.Fatalf("read error: %v", err)
	}
	buf = buf[:n]
	response := string(buf)
	logger.Printf(response)
	datatypeOutputStreamMap := make(map[string]string)

	var responseObjet AgentTaggedDataResponse
	err = json.Unmarshal([]byte(response), &responseObjet)
	if err != nil {
		logger.Printf("Windows AMA: Error::mdsd::Failed to unmarshal config data. Error message: %s", string(err.Error()))
	}
	f.Close()
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
