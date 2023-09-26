package lib

import (
	"testing"
	"os"
)

func TestGetResourceUri(t *testing.T) {
	// Save the original values of the environment variables
	originalServiceHost := os.Getenv("KUBERNETES_SERVICE_HOST")
	originalServicePort := os.Getenv("KUBERNETES_PORT_443_TCP_PORT")

	// Clean up the environment variables after the test is finished
	defer func() {
		os.Setenv("KUBERNETES_SERVICE_HOST", originalServiceHost)
		os.Setenv("KUBERNETES_PORT_443_TCP_PORT", originalServicePort)
	}()

	// Test case 1: KUBERNETES_SERVICE_HOST and KUBERNETES_PORT_443_TCP_PORT are set
	os.Setenv("KUBERNETES_SERVICE_HOST", "example.com")
	os.Setenv("KUBERNETES_PORT_443_TCP_PORT", "443")

	// Test getResourceUri for api_group == nil
	expectedURI := "https://example.com:443/api/" + ApiVersion + "/resource"
	uri, err := getResourceUri("resource", nil)
	if err != nil {
		t.Errorf("Expected no error, but got: %v", err)
	}
	if uri != expectedURI {
		t.Errorf("Expected URI to be %s, but got %s", expectedURI, uri)
	}

	// Test getResourceUri for api_group == ApiGroupApps
	apiGroupApps := ApiGroupApps
	expectedURI = "https://example.com:443/apis/apps/" + ApiVersionApps + "/resource"
	uri, err = getResourceUri("resource", &apiGroupApps)
	if err != nil {
		t.Errorf("Expected no error, but got: %v", err)
	}
	if uri != expectedURI {
		t.Errorf("Expected URI to be %s, but got %s", expectedURI, uri)
	}

	// Test getResourceUri for api_group == ApiGroupHPA
	apiGroupHPA := ApiGroupHPA
	expectedURI = "https://example.com:443/apis/" + ApiGroupHPA + "/" + ApiVersionHPA + "/resource"
	uri, err = getResourceUri("resource", &apiGroupHPA)
	if err != nil {
		t.Errorf("Expected no error, but got: %v", err)
	}
	if uri != expectedURI {
		t.Errorf("Expected URI to be %s, but got %s", expectedURI, uri)
	}

	// Test getResourceUri for unsupported api_group
	apiGroupUnknown := "unknown"
	_, err = getResourceUri("resource", &apiGroupUnknown)
	expectedErr := "unsupported API group: unknown"
	if err == nil || err.Error() != expectedErr {
		t.Errorf("Expected error: %s, but got: %v", expectedErr, err)
	}

	// Test case 2: KUBERNETES_SERVICE_HOST and KUBERNETES_PORT_443_TCP_PORT are not set
	os.Unsetenv("KUBERNETES_SERVICE_HOST")
	os.Unsetenv("KUBERNETES_PORT_443_TCP_PORT")

	_, err = getResourceUri("resource", nil)
	expectedErr = "environment variables not set"
	if err == nil || err.Error() != expectedErr {
		t.Errorf("Expected error: %s, but got: %v", expectedErr, err)
	}
}
