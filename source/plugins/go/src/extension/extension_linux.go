//go:build linux

package extension

import (
	"os"
	"strings"

	"github.com/ugorji/go/codec"
)

const FluentSocketAddress = "/var/run/mdsd-ci/default_fluent.socket"
const FluentSocketAddressPrometheusSidecar = "/var/run/mdsd-PrometheusSidecar/default_fluent.socket"

func getExtensionConfigResponse(jsonBytes []byte) ([]byte, error) {
	var data []byte
	enc := codec.NewEncoderBytes(&data, new(codec.MsgpackHandle))
	if err := enc.Encode(string(jsonBytes)); err != nil {
		return nil, err
	}

	fs := &FluentSocket{}
	fs.sockAddress = FluentSocketAddress
	genevaLogsIntegrationEnabled := strings.TrimSpace(strings.ToLower(os.Getenv("GENEVA_LOGS_INTEGRATION")))
	if (containerType != "" && strings.Compare(strings.ToLower(containerType), "prometheussidecar") == 0) ||
		(genevaLogsIntegrationEnabled != "" && strings.Compare(strings.ToLower(genevaLogsIntegrationEnabled), "true") == 0) {
		fs.sockAddress = FluentSocketAddressPrometheusSidecar
	}
	responseBytes, err := FluentSocketWriter.writeAndRead(fs, data)
	defer FluentSocketWriter.disconnect(fs)
	if err != nil {
		logger.Printf("Error::mdsd::Failed to write and read the config data. Error message: %s", string(err.Error()))
		return nil, err
	}
	return responseBytes, nil
}
