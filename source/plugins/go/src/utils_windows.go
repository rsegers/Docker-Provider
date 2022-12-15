//go:build windows

package main

import (
	"context"
	"syscall"
	"time"

	"github.com/Microsoft/go-winio"
)

func CreateWindowsNamedPipesClient(namedPipe string) {
	containerLogPipePath := "\\\\.\\\\pipe\\\\" + namedPipe

	Log("AMA::%s", containerLogPipePath)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	conn, err := winio.DialPipeAccess(ctx, containerLogPipePath, syscall.GENERIC_WRITE)

	if err != nil {
		Log("Error::AMA::Unable to open Named Pipe %s", err.Error())
	} else {
		Log("Windows Named Pipe opened without any errors")
		ContainerLogNamedPipe = conn
	}

}

