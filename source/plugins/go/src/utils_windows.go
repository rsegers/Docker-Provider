//go:build windows

package main

import (
	"context"
	"errors"
	"net"
	"syscall"
	"time"

	"github.com/Microsoft/go-winio"
)

func CreateWindowsNamedPipeClient(namedPipe string, namedPipeConnection *net.Conn) error {
	if namedPipe == "" {
		return errors.New("Error::AMA::CreateWindowsNamedPipeClient::namedPipe is empty")
	}
	containerLogPipePath := "\\\\.\\\\pipe\\\\" + namedPipe

	Log("AMA::CreateWindowsNamedPipeClient::The named pipe is: %s", containerLogPipePath)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	conn, err := winio.DialPipeAccess(ctx, containerLogPipePath, syscall.GENERIC_WRITE)

	if err != nil {
		return err
	} else {
		Log("Windows Named Pipe opened without any errors")
		*namedPipeConnection = conn
	}
	return nil
}

func EnsureGenevaOr3PNamedPipeExists(namedPipeConnection *net.Conn, datatype string, errorCount *float64, isGenevaLogsIntegrationEnabled bool, refreshTracker *time.Time) bool {
	if *namedPipeConnection == nil {
		Log("Error::AMA:: The connection to named pipe was nil. re-connecting...")
		var err error
		if isGenevaLogsIntegrationEnabled {
			err = CreateWindowsNamedPipeClient(getGenevaWindowsNamedPipeName(), namedPipeConnection)
		} else {
			err = CreateWindowsNamedPipeClient(GetOutputNamedPipe(datatype, refreshTracker), namedPipeConnection)
		}

		if err != nil || namedPipeConnection == nil {
			Log("Error::AMA::Cannot create the named pipe connection for %s.", datatype)
			ContainerLogTelemetryMutex.Lock()
			defer ContainerLogTelemetryMutex.Unlock()
			*errorCount += 1
			return false
		}
	}
	return true
}
