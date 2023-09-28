package main

import (
	"Docker-Provider/source/plugins/go/input/lib"
	"Docker-Provider/source/plugins/go/src/extension"
	"context"
	"errors"
	"log"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/calyptia/plugin"
)

// Plugin needs to be registered as an input type plugin in the initialisation phase
func init() {
	plugin.RegisterInput("containerinventory", "fluent-bit input plugin for containerinventory", &containerInventoryPlugin{})
}

type containerInventoryPlugin struct {
	tag         string
	runInterval int
}

var (
	FLBLogger                 *log.Logger
	namespaceFilteringMode    = "off"
	namespaces                []string
	addonTokenAdapterImageTag = ""
	agentConfigRefreshTracker = time.Now().Unix()
	tag                       = "oneagent.containerInsights.CONTAINER_INVENTORY_BLOB"
	runInterval               = 60
	containerType             = os.Getenv("CONTAINER_TYPE")
	hostName                  = ""
	telemetryTimeTracker      int64
	isFromCache	       = false
)

// Init An instance of the configuration loader will be passed to the Init method so all the required
// configuration entries can be retrieved within the plugin context.
func (p *containerInventoryPlugin) Init(ctx context.Context, fbit *plugin.Fluentbit) error {
	if fbit.Conf.String("tag") == "" {
		p.tag = tag
	} else {
		p.tag = fbit.Conf.String("tag")
	}
	if fbit.Conf.String("run_interval") == "" {
		p.runInterval = runInterval
	} else {
		p.runInterval, _ = strconv.Atoi(fbit.Conf.String("run_interval"))
	}

	osType := os.Getenv("OS_TYPE")
	if strings.EqualFold(osType, "windows") {
		FLBLogger = lib.CreateLogger("/etc/amalogswindows/fluent-bit-input.log")
	} else {
		FLBLogger = lib.CreateLogger("/var/opt/microsoft/docker-cimprov/log/fluent-bit-input.log")
	}

	return nil
}

// Collect this method will be invoked by the fluent-bit engine after the initialisation is successful
// this method can lock as each plugin its implemented in its own thread. Be aware that the main context
// can be cancelled at any given time, so handle the context properly within this method.
// The *ch* channel parameter, is a channel handled by the runtime that will receive messages from the plugin
// collection, make sure to validate channel closure and to follow the `plugin.Message` struct for messages
// generated by plugins.
func (p containerInventoryPlugin) Collect(ctx context.Context, ch chan<- plugin.Message) error {
	tick := time.NewTicker(time.Duration(p.runInterval) * time.Second)

	for {
		select {
		case <-ctx.Done():
			err := ctx.Err()
			if err != nil && !errors.Is(err, context.Canceled) {
				return err
			}

			return nil
		case <-tick.C:
			emitTime := time.Now()
			telemetryTimeTracker = emitTime.Unix()
			FLBLogger.Print("containerinventory::enumerate.start @ ", time.Now().UTC().Format(time.RFC3339))
			messages := p.enumerate()
			FLBLogger.Print("containerinventory::enumerate.end @ ", time.Now().UTC().Format(time.RFC3339))

			ch <- plugin.Message{
				Record: map[string]any {
					"tag":     tag,
					"messages": messages,
				},
				Time: emitTime,
			}
			FLBLogger.Print("containerinventory::emitted ", len(messages) ," container inventory records @ ", time.Now().UTC().Format(time.RFC3339))

			timeDifference := int(math.Abs(float64(time.Now().Unix() - telemetryTimeTracker)))
			timeDifferenceInMinutes := timeDifference / 60

			if timeDifferenceInMinutes >= 5 {
				telemetryTimeTracker = time.Now().Unix()
				telemetryProperties := map[string]string{}
				telemetryProperties["Computer"] = hostName
				telemetryProperties["ContainerCount"] = strconv.Itoa(len(messages))
				if addonTokenAdapterImageTag != "" {
					telemetryProperties["addonTokenAdapterImageTag"] = addonTokenAdapterImageTag
				}
				lib.SendTelemetry("ContainerInventory", telemetryProperties) // Replace "PluginName" with the actual plugin name
			}
		}
	}
}

func (p containerInventoryPlugin) enumerate() []map[string]interface{} {
	currentTime := time.Now()
	batchTime := currentTime.UTC().Format(time.RFC3339)
	hostName = ""
	namespaceFilteringMode = "off"
	namespaces = []string{}
	tag = p.tag

	FLBLogger.Printf("containerinventory::enumerate: Begin processing @ %s", time.Now().UTC().Format(time.RFC3339))

	if lib.IsAADMSIAuthMode() {
		FLBLogger.Print("containerinventory::enumerate: AAD AUTH MSI MODE")
		e := extension.GetInstance(FLBLogger, containerType)

		tag, isFromCache = lib.GetOutputStreamIdAndSource(e, lib.ContainerInventoryDataType, tag, agentConfigRefreshTracker)
		if !isFromCache {
			agentConfigRefreshTracker = time.Now().Unix()
		}

		if !lib.IsDCRStreamIdTag(tag) {
			FLBLogger.Print("WARN::containerinventory::enumerate: skipping Microsoft-ContainerInventory stream since its opted-out @", time.Now().UTC().Format(time.RFC3339))
			return nil
		}

		if e.IsDataCollectionSettingsConfigured() {
			runInterval := e.GetDataCollectionIntervalSeconds()
			FLBLogger.Print("containerinventory::enumerate: using data collection interval(seconds):", runInterval, "@", time.Now().UTC().Format(time.RFC3339))

			namespaces := e.GetNamespacesForDataCollection()
			FLBLogger.Print("containerinventory::enumerate: using data collection namespaces:", namespaces, "@", time.Now().UTC().Format(time.RFC3339))

			namespaceFilteringMode := e.GetNamespaceFilteringModeForDataCollection()
			FLBLogger.Print("containerinventory::enumerate: using data collection filtering mode for namespaces:", namespaceFilteringMode, "@", time.Now().UTC().Format(time.RFC3339))
		}
	}

	containerRuntimeEnv := os.Getenv("CONTAINER_RUNTIME")
	FLBLogger.Printf("containerinventory::enumerate: container runtime : %s", containerRuntimeEnv)
	FLBLogger.Print("containerinventory::enumerate: using cadvisor apis")

	containerIds, containerInventory := lib.GetContainerInventory(namespaceFilteringMode, namespaces, batchTime)

	// Update the state for deleted containers
	deletedContainers := lib.GetDeletedContainers(containerIds)
	if len(deletedContainers) > 0 {
		for _, deletedContainer := range deletedContainers {
			container := lib.ReadContainerState(deletedContainer)
			if container != nil {
				for k, v := range container {
					container[k] = v
				}
				container["State"] = "Deleted"
				lib.DeleteCGroupCacheEntryForDeletedContainer(container["InstanceID"].(string))
				containerInventory = append(containerInventory, container)
			}
		}
	}

	isTestVar := os.Getenv("ISTEST")
	if strings.ToLower(isTestVar) == "true" && len(containerInventory) > 0 {
		FLBLogger.Printf("containerInventory::enumerate: containerInventoryEmitStreamSuccess @ %s", time.Now().UTC().Format(time.RFC3339))
	}
	FLBLogger.Printf("containerinventory::enumerate: Processing complete %s", time.Now().UTC().Format(time.RFC3339))
	return containerInventory
}

func main() {}
