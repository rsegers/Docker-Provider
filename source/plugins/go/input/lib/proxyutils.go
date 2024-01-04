package lib

import (
	"io/ioutil"
	"os"
	"strings"
)

var proxyCertPath = "/etc/ama-logs-secret/PROXYCERT.crt"

type ProxyConfiguration struct {
	User string
	Pass string
	Addr string
	Port string
}

// func getProxyConfiguration() map[string]string {
// 	amalogsproxySecretPath := "/etc/ama-logs-secret/PROXY"
// 	if _, err := os.Stat(amalogsproxySecretPath); os.IsNotExist(err) {
// 		return make(map[string]string)
// 	}

// 	proxyConfig, err := parseProxyConfiguration(amalogsproxySecretPath)
// 	if err != nil {
// 		// todo: handle error
// 		return make(map[string]string)
// 	}

// 	// todo: log if empty
// 	return proxyConfig
// }

func GetProxyEndpoint() string {
	amaLogsProxySecretPath := "/etc/ama-logs-secret/PROXY"
	proxyConfig, err := ioutil.ReadFile(amaLogsProxySecretPath)
	if err != nil {
		// todo: handle error
		return ""
	}
	return strings.TrimSpace(string(proxyConfig))
}

// func parseProxyConfiguration(proxyConfPath string) (map[string]string, error) {
// 	proxyConfBytes, err := ioutil.ReadFile(proxyConfPath)
// 	if err != nil {
// 		return nil, err
// 	}

// 	proxyConfStr := string(proxyConfBytes)
// 	if proxyConfStr == "" {
// 		return nil, nil
// 	}

// 	// Remove trailing / if the proxy endpoint has one
// 	proxyConfStr = strings.TrimSuffix(proxyConfStr, "/")

// 	// Remove the http(s) protocol
// 	proxyConfStr = strings.ReplaceAll(proxyConfStr, "https://", "")
// 	proxyConfStr = strings.ReplaceAll(proxyConfStr, "http://", "")

// 	// Check for unsupported protocol
// 	if strings.Contains(proxyConfStr, "://") {
// 		return nil, nil
// 	}

// 	re := regexp.MustCompile(`^(?:(?P<user>[^:]+):(?P<pass>[^@]+)@)?(?P<addr>[^:@]+)(?::(?P<port>\d+))?$`)
// 	matches := re.FindStringSubmatch(proxyConfStr)
// 	if len(matches) != 5 || matches[3] == "" {
// 		return nil, nil
// 	}

// 	proxyConfig := map[string]string{
// 		"user": matches[1],
// 		"pass": matches[2],
// 		"addr": matches[3],
// 		"port": matches[4],
// 	}

// 	return proxyConfig, nil
// }

func isProxyCACertConfigured() bool {
	_, err := os.Stat(proxyCertPath)
	// todo: add log
	return err == nil
}

func IsIgnoreProxySettings() bool {
	return strings.ToLower(os.Getenv("IGNORE_PROXY_SETTINGS")) == "true"
}
