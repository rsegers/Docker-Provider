package lib

import (
	"io/ioutil"
	"os"
	"strings"
	"testing"
)

func TestIsAADMSIAuthMode(t *testing.T) {
	// Test case 1: AAD_MSI_AUTH_MODE environment variable is not set
	os.Unsetenv("AAD_MSI_AUTH_MODE")
	if IsAADMSIAuthMode() {
		t.Error("Expected false, got true")
	}

	// Test case 2: AAD_MSI_AUTH_MODE is set to "false"
	os.Setenv("AAD_MSI_AUTH_MODE", "false")
	if IsAADMSIAuthMode() {
		t.Error("Expected false, got true")
	}

	// Test case 3: AAD_MSI_AUTH_MODE is set to "true" (case-insensitive)
	os.Setenv("AAD_MSI_AUTH_MODE", "true")
	if !IsAADMSIAuthMode() {
		t.Error("Expected true, got false")
	}

	// Test case 4: AAD_MSI_AUTH_MODE is set to "TRUE" (case-insensitive)
	os.Setenv("AAD_MSI_AUTH_MODE", "TRUE")
	if !IsAADMSIAuthMode() {
		t.Error("Expected true, got false")
	}
}

func TestGetHostname(t *testing.T) {
	// Test case 1: HOSTNAME environment variable is not set
	os.Unsetenv("HOSTNAME")
	if GetHostname() != "" {
		t.Error("Expected empty string, got non-empty string")
	}

	// Test case 2: HOSTNAME environment variable is set
	os.Setenv("HOSTNAME", "test-hostname")
	if GetHostname() != "test-hostname" {
		t.Error("Expected test-hostname, got something else")
	}
}

func TestLogger(t *testing.T) {
	testLogger := CreateLogger("./fluent-bit-container.log")
	if testLogger == nil {
		t.Error("Expected non-nil logger, got nil")
	}
	testLogger.Printf("Test log message")

	file, err := os.Open("./fluent-bit-container.log")
	if err != nil {
		t.Error(err)
	}
	defer file.Close()

	fileContents, _ := ioutil.ReadAll(file)

	if !strings.Contains(string(fileContents), "Test log message") {
		t.Error("Expected log message to be written to file, got nothing")
	}

	err = os.Remove("./fluent-bit-container.log")
	if err != nil {
		t.Error(err)
	}
}
