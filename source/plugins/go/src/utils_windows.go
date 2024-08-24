//go:build windows

package main

import (
	"context"
	"fmt"
	"net"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/Microsoft/go-winio"
)

func CreateWindowsNamedPipeClient(namedPipe string, namedPipeConnection *net.Conn) {
	if namedPipe == "" {
		Log("Error::AMA::CreateWindowsNamedPipeClient::namedPipe is empty")
		return
	}
	containerLogPipePath := "\\\\.\\\\pipe\\\\" + namedPipe

	Log("AMA::CreateWindowsNamedPipeClient::The named pipe is: %s", containerLogPipePath)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	conn, err := winio.DialPipeAccess(ctx, containerLogPipePath, syscall.GENERIC_WRITE)

	if err != nil {
		Log("Error::AMA::Unable to open Named Pipe %s", err.Error())
	} else {
		Log("Windows Named Pipe opened without any errors")
		*namedPipeConnection = conn
	}
}

func EnsureGenevaOr3PNamedPipeExists(namedPipeConnection *net.Conn, datatype string, errorCount *float64, isGenevaLogsIntegrationEnabled bool, refreshTracker *time.Time) bool {
	if *namedPipeConnection == nil {
		Log("Error::AMA:: The connection to named pipe was nil. re-connecting...")
		if isGenevaLogsIntegrationEnabled {
			CreateWindowsNamedPipeClient(getGenevaWindowsNamedPipeName(), namedPipeConnection)
		} else {
			CreateWindowsNamedPipeClient(GetOutputNamedPipe(datatype, refreshTracker), namedPipeConnection)
		}
		if namedPipeConnection == nil {
			Log("Error::AMA::Cannot create the named pipe connection for %s.", datatype)
			ContainerLogTelemetryMutex.Lock()
			defer ContainerLogTelemetryMutex.Unlock()
			*errorCount += 1
			return false
		}
	}
	return true
}

func isProcessRunning(processName string) (string, error) {
	cmd := exec.Command("tasklist", "/FI", fmt.Sprintf("IMAGENAME eq %s", processName))
	output, err := cmd.Output()

	if err != nil {
		return "false", err
	}

	outputStr := strings.TrimSpace(string(output))
	if strings.Contains(outputStr, "INFO: No tasks are running") {
		return "false", nil
	}
	if strings.Contains(outputStr, processName) {
		return "true", nil
	}

	return "false", nil
}
