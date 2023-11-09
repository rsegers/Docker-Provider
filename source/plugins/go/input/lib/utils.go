package lib

import (
	"fmt"
	"log"
	"os"
	"strings"

	lumberjack "gopkg.in/natefinch/lumberjack.v2"
)

func CreateLogger(logPath string) *log.Logger {
	var logfile *os.File
	if _, err := os.Stat(logPath); err == nil {
		fmt.Printf("File Exists. Opening file in append mode...\n")
		logfile, err = os.OpenFile(logPath, os.O_APPEND|os.O_WRONLY, 0600)
		if err != nil {
			SendException(err.Error())
			fmt.Println(err.Error())
		}
	}

	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		fmt.Printf("File Doesnt Exist. Creating file...\n")
		logfile, err = os.Create(logPath)
		if err != nil {
			SendException(err.Error())
			fmt.Println(err.Error())
		}
	}

	logger := log.New(logfile, "", 0)

	logger.SetOutput(&lumberjack.Logger{
		Filename:   logPath,
		MaxSize:    10, // megabytes
		MaxBackups: 1,
		MaxAge:     28,   // days
		Compress:   true, // false by default
	})

	logger.SetFlags(log.Ltime | log.Lshortfile | log.LstdFlags)
	return logger
}

func IsAADMSIAuthMode() bool {
	aadMSIAuthMode := os.Getenv("AAD_MSI_AUTH_MODE")
	return aadMSIAuthMode != "" && strings.ToLower(aadMSIAuthMode) == "true"
}

func GetHostname() string {
	return os.Getenv("HOSTNAME")
}
