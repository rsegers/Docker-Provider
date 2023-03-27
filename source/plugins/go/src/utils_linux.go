//go:build linux

package main

import "net"

func CreateWindowsNamedPipeClient(namedPipe string, namedPipeConnection *net.Conn) {
	//function unimplemented
	Log("Error::CreateWindowsNamedPipeClient not implemented for Linux")
}

func CheckIfNamedPipeCreated(namedPipeConnection *net.Conn, datatype string, errorCount *float64, isGenevaLogsIntegrationEnabled bool) bool {
	//function unimplemented
	Log("Error::CheckIfNamedPipeCreated not implemented for Linux")
	return false
}
