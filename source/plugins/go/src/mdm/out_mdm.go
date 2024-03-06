package mdm

// import (
// 	"github.com/fluent/fluent-bit-go/output"
// )
// import (
// 	"C"
// 	"os"
// 	"strings"
// 	"unsafe"
// )

// //export FLBPluginRegister
// func FLBPluginRegister(ctx unsafe.Pointer) int {
// 	return output.FLBPluginRegister(ctx, "mdm", "MDM GO!")
// }

// // (fluentbit will call this)
// // ctx (context) pointer to fluentbit context (state/ c code)
// //
// //export FLBPluginInit
// func FLBPluginInit(ctx unsafe.Pointer) int {
// 	Log("Initializing out_mdm go plugin for fluentbit")
// 	agentVersion := os.Getenv("AGENT_VERSION")
// 	InitializePlugin(agentVersion)

// 	enableTelemetry := output.FLBPluginConfigKey(ctx, "EnableTelemetry")
// 	if strings.Compare(strings.ToLower(enableTelemetry), "true") == 0 {
// 		telemetryPushInterval := output.FLBPluginConfigKey(ctx, "TelemetryPushIntervalSeconds")
// 		go SendMDMMetrics(telemetryPushInterval)
// 	} else {
// 		Log("Telemetry is not enabled for the plugin %s \n", output.FLBPluginConfigKey(ctx, "Name"))
// 		return output.FLB_OK
// 	}
// 	return output.FLB_OK
// }

// //export FLBPluginFlush
// func FLBPluginFlush(data unsafe.Pointer, length C.int, tag *C.char) int {
// 	var ret int
// 	var record map[interface{}]interface{}
// 	var records []map[interface{}]interface{}

// 	// Create Fluent Bit decoder
// 	dec := output.NewDecoder(data, int(length))

// 	// Iterate Records
// 	for {
// 		// Extract Record
// 		ret, _, record = output.GetRecord(dec)
// 		if ret != 0 {
// 			break
// 		}
// 		records = append(records, record)
// 	}

// 	incomingTag := strings.ToLower(C.GoString(tag))
// 	if strings.Contains(incomingTag, "mdm.container.perf.telegraf") {
// 		return PostTelegrafMetricsToMDM(records)
// 	} else if strings.Contains(incomingTag, "oneagent.containerinsights.LINUX_PERF_BLOB") {
// 		return PostCAdvisorMetricsToMDM(records)
// 	}

// 	return output.FLB_OK
// }

// // FLBPluginExit exits the plugin
// func FLBPluginExit() int {
// 	return output.FLB_OK
// }

func main() {
}
