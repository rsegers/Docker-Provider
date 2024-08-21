//go:build linux

package main

import (
	"net"
	"os/exec"
	"strings"
	"time"
)

func CreateWindowsNamedPipeClient(namedPipe string, namedPipeConnection *net.Conn) {
	//function unimplemented
	Log("Error::CreateWindowsNamedPipeClient not implemented for Linux")
}

func EnsureGenevaOr3PNamedPipeExists(namedPipeConnection *net.Conn, datatype string, errorCount *float64, isGenevaLogsIntegrationEnabled bool, refreshTracker *time.Time) bool {
	//function unimplemented
	Log("Error::EnsureGenevaOr3PNamedPipeExists not implemented for Linux")
	return false
}

func isTelegrafRunning() bool {
	cmd := exec.Command("pgrep", "telegraf")
	output, err := cmd.Output()

	if err == nil && len(strings.TrimSpace(string(output))) > 0 {
		return true
	}
	return false
}
