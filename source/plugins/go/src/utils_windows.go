//go:build windows

package main

import (
	"Docker-Provider/source/plugins/go/src/extension"
	"context"
	"net"

	// "os"
	"syscall"
	"time"

	"github.com/Microsoft/go-winio"
)

// var lockFile *os.File
// var err error

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

func CheckIfNamedPipeCreated(namedPipeConnection *net.Conn, datatype string, errorCount *float64, isGenevaLogsIntegrationEnabled bool) bool {
	if *namedPipeConnection == nil {
		Log("Error::AMA:: The connection to named pipe was nil. re-connecting...")
		if isGenevaLogsIntegrationEnabled {
			CreateWindowsNamedPipeClient(getGenevaWindowsNamedPipeName(), namedPipeConnection)
		} else {
			CreateWindowsNamedPipeClient(extension.GetInstance(FLBLogger, ContainerType).GetOutputNamedPipe(datatype), namedPipeConnection)
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

// func GetFileLock() error {
// 	lockFilePath := "/etc/amalogswindows/filelock_ama"
// 	lockFile, err = os.OpenFile(lockFilePath, os.O_CREATE|os.O_RDWR, 0666)
// 	if err != nil {
// 		Log("Error opening the lockfile: %s", err)
// 		return err
// 	}
// 	err = syscall.Flock(int(lockFile.Fd()), syscall.LOCK_EX)
// 	if err != nil {
// 		Log("Error getting the access of the file: %s", err)
// 		return err
// 	}
// 	return nil
// }

// func ReleaseFileLock() error {
// 	// Release the lock and close the file
// 	unlock_err := syscall.Flock(int(lockFile.Fd()), syscall.LOCK_UN)
// 	if unlock_err != nil {
// 		Log("Error releasing lock:", unlock_err)
// 	}
// 	lockFile.Close()
// }
