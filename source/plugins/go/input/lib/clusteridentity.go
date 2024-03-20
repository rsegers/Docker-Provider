package lib

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

// Constants
const (
	ClusterConfigCRDAPIVersion          = "clusterconfig.azure.com/v1beta1"
	ClusterIdentityResourceName         = "container-insights-clusteridentityrequest"
	ClusterIdentityResourceNamespace    = "azure-arc"
	ClusterIdentityTokenSecretNamespace = "azure-arc"
	CRResourceURITemplate               = "%s/apis/%s/namespaces/%s/azureclusteridentityrequests/%s"
	SecretResourceURITemplate           = "%s/api/v1/namespaces/%s/secrets/%s"
	AzureMonitorCustomMetricsAudience   = "https://monitoring.azure.com/"
	ClusterIdentityRequestKind          = "AzureClusterIdentityRequest"
)

// ArcK8sClusterIdentity struct represents the Ruby class
type ArcK8sClusterIdentity struct {
	LogPath                         string
	Logger                          *log.Logger
	TokenExpiryTime                 time.Time
	CachedAccessToken               string
	IsLastTokenRenewalUpdatePending bool
	TokenFilePath                   string
	CertFilePath                    string
	KubeAPIServerURL                string
	HTTPClient                      *http.Client
	ServiceAccountToken             string
	ExtensionName                   string
}

// NewArcK8sClusterIdentity creates a new instance of ArcK8sClusterIdentity
func NewArcK8sClusterIdentity() *ArcK8sClusterIdentity {
	osType := os.Getenv("OS_TYPE")
	logPath := "/var/opt/microsoft/docker-cimprov/log/arc_k8s_cluster_identity.log"
	if strings.ToLower(strings.TrimSpace(osType)) == "windows" {
		logPath = "/etc/amalogswindows/arc_k8s_cluster_identity.log"
	}

	isTestEnv := os.Getenv("ISTEST") == "true"
	if isTestEnv {
		logPath = "./arc_k8s_cluster_identity.log"
	}

	logger := CreateLogger(logPath)

	arcK8sClusterIdentity := &ArcK8sClusterIdentity{
		LogPath:                         logPath,
		Logger:                          logger,
		TokenExpiryTime:                 time.Now(),
		CachedAccessToken:               "",
		IsLastTokenRenewalUpdatePending: false,
		TokenFilePath:                   "/var/run/secrets/kubernetes.io/serviceaccount/token",
		CertFilePath:                    "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
		ExtensionName:                   os.Getenv("ARC_K8S_EXTENSION_NAME"),
	}

	arcK8sClusterIdentity.KubeAPIServerURL = GetKubeAPIServerUrl()
	arcK8sClusterIdentity.HTTPClient = arcK8sClusterIdentity.GetHTTPClient()
	arcK8sClusterIdentity.ServiceAccountToken = arcK8sClusterIdentity.GetServiceAccountToken()

	return arcK8sClusterIdentity
}

func (a *ArcK8sClusterIdentity) GetClusterIdentityToken() (string, error) {
	// Check if the token is empty or near expiry
	if a.CachedAccessToken == "" || time.Now().Add(60*time.Minute).After(a.TokenExpiryTime) {
		if a.CachedAccessToken != "" && time.Now().Add(60*time.Minute).After(a.TokenExpiryTime) {
			if !a.IsLastTokenRenewalUpdatePending {
				a.Logger.Printf("Token expiry: %v", a.TokenExpiryTime)
				a.Logger.Println("Renewing the token due to near expiry")
				err := a.RenewNearExpiryToken()
				if err != nil {
					return "", err
				}
				time.Sleep(60 * time.Second)
				a.IsLastTokenRenewalUpdatePending = true
			} else {
				a.Logger.Println("Last token renewal update still pending")
			}
		}
		a.Logger.Println("Getting token reference from CRD")
		tokenReference, err := a.GetTokenReferenceFromCRD()
		if err != nil {
			return "", err
		}
		if tokenReference != nil {
			expirationTime, err := time.Parse(time.RFC3339, tokenReference["expirationTime"])
			if err != nil {
				return "", err
			}
			a.TokenExpiryTime = expirationTime
			tokenSecretName := tokenReference["secretName"]
			tokenSecretDataName := tokenReference["dataName"]
			token, err := a.GetTokenFromSecret(tokenSecretName, tokenSecretDataName)
			if err != nil {
				return "", err
			}
			a.CachedAccessToken = token
			a.IsLastTokenRenewalUpdatePending = false
		} else {
			a.Logger.Println("Token reference is nil or empty")
		}
	}
	return a.CachedAccessToken, nil
}

func (a *ArcK8sClusterIdentity) GetTokenFromSecret(tokenSecretName, tokenSecretDataName string) (string, error) {
	secretResourceURI := fmt.Sprintf(SecretResourceURITemplate, a.KubeAPIServerURL, ClusterIdentityTokenSecretNamespace, tokenSecretName)
	req, err := http.NewRequest("GET", secretResourceURI, nil)
	if err != nil {
		return "", err
	}
	req.Header.Add("Authorization", "Bearer "+a.ServiceAccountToken)

	a.Logger.Printf("Making GET request to %s", secretResourceURI)
	resp, err := a.HTTPClient.Do(req)
	if err != nil {
		SendExceptionTelemetry(err.Error(), map[string]string{"FeatureArea": "MDMGo"})
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		var secretData map[string]interface{}
		if err := json.NewDecoder(resp.Body).Decode(&secretData); err != nil {
			return "", err
		}

		tokenEncoded, ok := secretData["data"].(map[string]interface{})[tokenSecretDataName].(string)
		if !ok {
			return "", errors.New("token not found in secret data")
		}
		token, err := base64.StdEncoding.DecodeString(tokenEncoded)
		if err != nil {
			return "", err
		}
		return string(token), nil
	}

	return "", fmt.Errorf("failed to get token from secret: HTTP %d", resp.StatusCode)
}

func (a *ArcK8sClusterIdentity) GetTokenReferenceFromCRD() (map[string]string, error) {
	crdResourceURI := fmt.Sprintf(CRResourceURITemplate, a.KubeAPIServerURL, ClusterConfigCRDAPIVersion, ClusterIdentityResourceNamespace, ClusterIdentityResourceName)
	req, err := http.NewRequest("GET", crdResourceURI, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Add("Authorization", "Bearer "+a.ServiceAccountToken)

	a.Logger.Printf("Making GET request to %s", crdResourceURI)
	resp, err := a.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		var crdResponse map[string]interface{}
		if err := json.NewDecoder(resp.Body).Decode(&crdResponse); err != nil {
			return nil, err
		}

		status, ok := crdResponse["status"].(map[string]interface{})
		if !ok {
			return nil, errors.New("status not found in CRD response")
		}

		tokenReference := make(map[string]string)
		tokenReference["expirationTime"] = status["expirationTime"].(string)
		tokenRef, ok := status["tokenReference"].(map[string]interface{})
		if !ok {
			return nil, errors.New("tokenReference not found in status")
		}
		tokenReference["secretName"] = tokenRef["secretName"].(string)
		tokenReference["dataName"] = tokenRef["dataName"].(string)

		return tokenReference, nil
	}

	return nil, fmt.Errorf("failed to get token reference from CRD: HTTP %d", resp.StatusCode)
}

func (a *ArcK8sClusterIdentity) RenewNearExpiryToken() error {
	crdResourceURI := fmt.Sprintf(CRResourceURITemplate, a.KubeAPIServerURL, ClusterConfigCRDAPIVersion, ClusterIdentityResourceNamespace, ClusterIdentityResourceName)
	updateCrdRequestURI := crdResourceURI + "/status"

	updateCrdRequestBody := map[string]interface{}{
		"status": map[string]string{"expirationTime": ""},
	}
	updateCrdRequestBodyJSON, err := json.Marshal(updateCrdRequestBody)
	if err != nil {
		return err
	}

	req, err := http.NewRequest("PATCH", updateCrdRequestURI, bytes.NewReader(updateCrdRequestBodyJSON))
	if err != nil {
		return err
	}
	req.Header.Add("Content-Type", "application/merge-patch+json")
	req.Header.Add("Authorization", "Bearer "+a.ServiceAccountToken)

	a.Logger.Printf("Making PATCH request to %s", updateCrdRequestURI)
	resp, err := a.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to renew token: HTTP %d", resp.StatusCode)
	}

	return nil
}

func (a *ArcK8sClusterIdentity) GetServiceAccountToken() string {
	if _, err := os.Stat(a.TokenFilePath); os.IsNotExist(err) || err != nil {
		a.Logger.Printf("Unable to read token string from %s: %v", a.TokenFilePath, err)
		return ""
	}

	tokenStr, err := ioutil.ReadFile(a.TokenFilePath)
	if err != nil {
		a.Logger.Printf("get_service_account_token call failed: %v", err)
		SendExceptionTelemetry(err.Error(), map[string]string{"FeatureArea": "MDMGo"})
		return ""
	}

	return strings.TrimSpace(string(tokenStr))
}

func (a *ArcK8sClusterIdentity) GetHTTPClient() *http.Client {
	baseAPIServerURL, err := url.Parse(a.KubeAPIServerURL)
	if err != nil {
		a.Logger.Printf("Unable to parse API server URL %s: %v", a.KubeAPIServerURL, err)
		return nil
	}

	httpClient := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				RootCAs: x509.NewCertPool(),
			},
		},
	}

	if _, err := os.Stat(a.CertFilePath); os.IsNotExist(err) {
		a.Logger.Printf("%s doesn't exist: %v", a.CertFilePath, err)
		return nil
	}

	caCert, err := ioutil.ReadFile(a.CertFilePath)
	if err != nil {
		a.Logger.Printf("Unable to read cert file %s: %v", a.CertFilePath, err)
		return nil
	}

	httpClient.Transport.(*http.Transport).TLSClientConfig.RootCAs.AppendCertsFromPEM(caCert)
	httpClient.Transport.(*http.Transport).TLSClientConfig.ServerName = baseAPIServerURL.Hostname()

	return httpClient
}

func (a *ArcK8sClusterIdentity) GetCRDRequestBody() map[string]interface{} {
	body := map[string]interface{}{
		"apiVersion": ClusterConfigCRDAPIVersion,
		"kind":       ClusterIdentityRequestKind,
		"metadata": map[string]string{
			"name":      ClusterIdentityResourceName,
			"namespace": ClusterIdentityResourceNamespace,
		},
		"spec": map[string]string{
			"audience": AzureMonitorCustomMetricsAudience,
		},
	}

	if a.ExtensionName != "" {
		body["spec"].(map[string]string)["resourceId"] = a.ExtensionName
	}

	return body
}
