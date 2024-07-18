//go:build linux

package main

import (
	"errors"
	"net"
	"time"
)

func CreateWindowsNamedPipeClient(namedPipe string, namedPipeConnection *net.Conn) error {
	return errors.New("Error::CreateWindowsNamedPipeClient not implemented for Linux")
}

func EnsureGenevaOr3PNamedPipeExists(namedPipeConnection *net.Conn, datatype string, errorCount *float64, isGenevaLogsIntegrationEnabled bool, refreshTracker *time.Time) bool {
	//function unimplemented
	Log("Error::EnsureGenevaOr3PNamedPipeExists not implemented for Linux")
	return false
}
