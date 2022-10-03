package extension

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"

	winio "github.com/Microsoft/go-winio"
	uuid "github.com/google/uuid"
	"github.com/ugorji/go/codec"
)

type Extension struct {
	datatypeStreamIdMap map[string]string
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

	var data []byte
	enc := codec.NewEncoderBytes(&data, new(codec.MsgpackHandle))
	if err := enc.Encode(string(jsonBytes)); err != nil {
		return datatypeOutputStreamMap, err
	}

	fs := &FluentSocket{}
	fs.sockAddress = "/var/run/mdsd/default_fluent.socket"
	if containerType != "" && strings.Compare(strings.ToLower(containerType), "prometheussidecar") == 0 {
		fs.sockAddress = fmt.Sprintf("/var/run/mdsd-%s/default_fluent.socket", containerType)
	}
	responseBytes, err := FluentSocketWriter.writeAndRead(fs, data)
	defer FluentSocketWriter.disconnect(fs)
	logger.Printf("Info::mdsd::Making call to FluentSocket: %s to write and read the config data", fs.sockAddress)
	if err != nil {
		return datatypeOutputStreamMap, err
	}
	response := string(responseBytes) // TODO: why is this converted to a string then back into a []byte?

	var responseObjet AgentTaggedDataResponse
	err = json.Unmarshal([]byte(response), &responseObjet)
	if err != nil {
		logger.Printf("Error::mdsd::Failed to unmarshal config data. Error message: %s", string(err.Error()))
		return datatypeOutputStreamMap, err
	}

	var extensionData TaggedData
	json.Unmarshal([]byte(responseObjet.TaggedData), &extensionData)

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

	logger.Printf("extensionconfig::getDataTypeToStreamIdMapping:: getting extension config from fluent socket-end")

	return datatypeOutputStreamMap, nil
}

func getOutputNamedPipe(datatype string) string {
	//implement this
	return "hello"
}

func getDataTypeToNamedPipeMapping() (map[string]string, error) {
	pipePath := `\\.\\pipe\\CAgentStream_CloudAgentInfo_AzureMonitorAgent`
	f, err := winio.DialPipe(pipePath, nil)
	if err != nil {
		log.Fatalf("error opening pipe: %v", err)
	}
	fmt.Println(f)
	defer f.Close()

	guid := uuid.New()
	taggedData := map[string]interface{}{"Request": "AgentTaggedData", "RequestId": guid.String(), "Tag": "ContainerInsights", "Version": "1"}
	jsonBytes, err := json.Marshal(taggedData)

	n, err := f.Write([]byte(jsonBytes))
	if err != nil {
		log.Fatalf("write error: %v", err)
	}
	log.Println("wrote:", n)

	buf := make([]byte, 262144)
	n, err = f.Read(buf)
	if err != nil {
		log.Fatalf("read error: %v", err)
	}
	buf = buf[:n]
	response := string(buf)
	fmt.Println(response)
	datatypeOutputStreamMap := make(map[string]string)

	var responseObjet AgentTaggedDataResponse
	err = json.Unmarshal([]byte(response), &responseObjet)
	if err != nil {
		fmt.Println("Error::mdsd::Failed to unmarshal config data. Error message: %s", string(err.Error()))
	}
	f.Close()
	var extensionData TaggedData
	json.Unmarshal([]byte(responseObjet.TaggedData), &extensionData)

	extensionConfigs := extensionData.ExtensionConfigs
	outputStreamDefinitions := extensionData.OutputStreamDefinitions
	fmt.Println("Info::mdsd::build the datatype and streamid map -- start")
	for _, extensionConfig := range extensionConfigs {
		outputStreams := extensionConfig.OutputStreams
		for dataType, outputStreamID := range outputStreams {
			fmt.Println("Info::mdsd::datatype: %s, outputstreamId: %s", dataType, outputStreamID)
			datatypeOutputStreamMap[dataType] = outputStreamDefinitions[outputStreamID.(string)].NamedPipe
		}
	}
	fmt.Println("The data map is -------------------------------------------------------")
	fmt.Println(datatypeOutputStreamMap)
	fmt.Println("----------------------------------------------------------")
	return datatypeOutputStreamMap, nil

}
