package mdm

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"math"
	"net"
	"net/http"
	_ "net/http/pprof"
	"net/url"
	"os"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"github.com/fluent/fluent-bit-go/output"
	"github.com/google/uuid"

	"Docker-Provider/source/plugins/go/input/lib"
)

var (
	tokenResourceURL              string
	tokenResourceAudience         string
	grantType                     string
	azureJSONPath                 string
	publicMetricsEndpointTemplate string
	postRequestURLTemplate        string
	aadTokenURLTemplate           string
	msiEndpointTemplate           string
	imdsMsiEndpointTemplate       string
	userAssignedClientID          string
	postRequestURI                *url.URL
	recordBatchSize               int
	tokenRefreshBackOffInterval   time.Duration

	dataHash                         map[string]interface{}
	parsedTokenURI                   *url.URL
	tokenExpiryTime                  time.Time
	cachedAccessToken                string
	lastPostAttemptTime              time.Time
	firstPostAttemptMade             bool
	canSendDataToMDM                 bool
	lastTelemetrySentTime            time.Time
	useMsi                           bool
	isAADMSIAuth                     bool
	isWindows                        bool
	metricsFlushedCount              int
	isArcK8sCluster                  bool
	getAccessTokenBackoffExpiry      time.Time
	mdmExceptionsHash                map[string]int
	mdmExceptionsCount               int
	mdmExceptionTelemetryTimeTracker int64
	proxyEndpoint                    string // Proxy endpoint in format http(s)://<user>:<pwd>@<proxyserver>:<port>
	controllerType                   string = strings.ToLower(os.Getenv("CONTROLLER_TYPE"))
	metricsToCollectHash             map[string]bool

	containerResourceUtilTelemetryTimeTracker int64
	pvUsageTelemetryTimeTracker               int64
	containersExceededCpuThreshold            bool
	containersExceededMemRssThreshold         bool
	containersExceededMemWorkingSetThreshold  bool
	pvExceededUsageThreshold                  bool
	cpuCapacity                               float64
	memoryCapacity                            float64
	cpuAllocatable                            float64
	memoryAllocatable                         float64
	containerCpuLimitHash                     map[string]float64
	containerMemoryLimitHash                  map[string]float64
	containerResourceDimensionHash            map[string]string
	metricsThresholdHash                      map[string]float64
	processIncomingStream                     bool
	clusterIdentity                           *lib.ArcK8sClusterIdentity
	Log 					  *log.Logger
)

func init() {
	tokenResourceURL = "https://monitoring.azure.com/"
	tokenResourceAudience = "https://monitor.azure.com/"
	grantType = "client_credentials"
	azureJSONPath = "/etc/kubernetes/host/azure.json"
	publicMetricsEndpointTemplate = "https://%s.monitoring.azure.com"
	postRequestURLTemplate = "%s%s/metrics"
	aadTokenURLTemplate = "https://login.microsoftonline.com/%s/oauth2/token"
	msiEndpointTemplate = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&client_id=%s&resource=%s"
	imdsMsiEndpointTemplate = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=%s"
	userAssignedClientID = os.Getenv("USER_ASSIGNED_IDENTITY_CLIENT_ID")
	recordBatchSize = 2000
	tokenRefreshBackOffInterval = 30 * time.Minute

	dataHash = make(map[string]interface{})
	tokenExpiryTime = time.Now()
	cachedAccessToken = ""
	lastPostAttemptTime = time.Now()
	firstPostAttemptMade = false
	canSendDataToMDM = true
	useMsi = false
	isAADMSIAuth = false
	isWindows = false
	metricsFlushedCount = 0
	isArcK8sCluster = false
	getAccessTokenBackoffExpiry = time.Now()
	mdmExceptionsHash = make(map[string]int)
	mdmExceptionsCount = 0
	mdmExceptionTelemetryTimeTracker = time.Now().Unix()

	isWindows = strings.Contains(strings.ToLower(os.Getenv("OS_TYPE")), "windows")
	var logPath string
	if isWindows {
		logPath = "/etc/amalogswindows/fluent-bit-mdm.log"
	} else {
		logPath = "/var/opt/microsoft/docker-cimprov/log/fluent-bit-mdm.log"
	}

	isTestEnv := strings.EqualFold(os.Getenv("ISTEST"), "true")
	if isTestEnv {
		logPath = "./fluent-bit-mdm.log"
	}

	Log = lib.CreateLogger(logPath)
}

// InitializePlugin reads and populates plugin configuration
func InitializePlugin(agentVersion string) {

	defer func() {
		if r := recover(); r != nil {
			stacktrace := debug.Stack()
			Log.Printf("MDMLog: Error initializing mdm plugin: %v, stacktrace: %v", r, stacktrace)
			lib.SendExceptionTelemetry(fmt.Sprintf("Error: %v, stackTrace: %v", r, stacktrace), map[string]string{ "FeatureArea": "MDMGo" })
		}
	}()

	aksResourceID := os.Getenv("AKS_RESOURCE_ID")
	aksRegion := os.Getenv("AKS_REGION")

	if aksResourceID == "" {
		Log.Printf("MDMLog: Environment Variable AKS_RESOURCE_ID is not set..")
		canSendDataToMDM = false
	} else if !strings.Contains(strings.ToLower(aksResourceID), "/microsoft.containerservice/managedclusters/") &&
		!strings.Contains(strings.ToLower(aksResourceID), "/microsoft.kubernetes/connectedclusters/") &&
		!strings.Contains(strings.ToLower(aksResourceID), "/microsoft.hybridcontainerservice/provisionedclusters/") {
		Log.Printf("MDMLog: MDM Metrics not supported for this cluster type resource: %s\n", aksResourceID)
		canSendDataToMDM = false
	}

	if aksRegion == "" {
		Log.Printf("MDMLog: Environment Variable AKS_REGION is not set..")
		canSendDataToMDM = false
	} else {
		aksRegion = strings.ReplaceAll(aksRegion, " ", "")
	}

	if !canSendDataToMDM {
		Log.Printf("MDMLog: MDM Metrics not supported for this cluster")
		return
	}

	isAADMSIAuth = false
	if strings.Compare(strings.ToLower(os.Getenv(AADMSIAuthMode)), "true") == 0 {
		isAADMSIAuth = true
		Log.Printf("MDMLog: AAD MSI Auth Mode Configured")
	}

	if strings.Contains(strings.ToLower(aksResourceID), "microsoft.kubernetes/connectedclusters") ||
		strings.Contains(strings.ToLower(aksResourceID), "microsoft.hybridcontainerservice/provisionedclusters") {
		isArcK8sCluster = true
	}

	customMetricsEndpoint := os.Getenv("CUSTOM_METRICS_ENDPOINT")
	var metricsEndpoint string
	if customMetricsEndpoint != "" {
		metricsEndpoint = strings.TrimSpace(customMetricsEndpoint)
		// URL parsing for validation
		if _, err := url.Parse(metricsEndpoint); err != nil {
			Log.Printf("MDMLog: Error parsing CUSTOM_METRICS_ENDPOINT: %v\n", err)
			return
		}
	} else {
		metricsEndpoint = fmt.Sprintf(publicMetricsEndpointTemplate, aksRegion)
	}
	postRequestURL := fmt.Sprintf(postRequestURLTemplate, metricsEndpoint, aksResourceID)
	var err error
	postRequestURI, err = url.Parse(postRequestURL)
	if err != nil {
		Log.Printf("MDMLog: Error parsing post request URL: %v\n", err)
		return
	}

	if lib.IsIgnoreProxySettings() {
		Log.Printf("MDMLog: Ignoring reading of proxy configuration since ignoreProxySettings is true")
	} else {
		// read proxyEndpoint if proxy configured
		proxyEndpoint = ""
		if isWindows {
			proxyEndpoint = os.Getenv("PROXY")

		} else {
			proxyEndpoint, err = lib.GetProxyEndpoint()
			if err != nil {
				Log.Printf("MDMLog: Error reading proxy endpoint: %v\n", err)
			}
		}

	}
	lib.SendCustomEvent("AKSCustomMetricsMDMGoPluginStart", nil)

	if isArcK8sCluster {
		if isAADMSIAuth && !isWindows {
			Log.Printf("MDMLog: using IMDS sidecar endpoint for MSI token since its Arc k8s and Linux node")
			useMsi = true

			customResourceEndpoint := os.Getenv("customResourceEndpoint")
			if customResourceEndpoint != "" {
				tokenResourceAudience = strings.TrimSpace(customResourceEndpoint)
			}

			msiEndpoint := fmt.Sprintf(imdsMsiEndpointTemplate, tokenResourceAudience)
			var err error
			parsedTokenURI, err = url.Parse(msiEndpoint)
			if err != nil {
				Log.Printf("MDMLog: Error parsing MSI endpoint URL: %v\n", err)
			}
		} else {
			Log.Printf("MDMLog: using cluster identity token since cluster is azure arc k8s cluster")
			clusterIdentity = lib.NewArcK8sClusterIdentity()
		}
	} else {
		fileContent, err := os.ReadFile(azureJSONPath)
		if err != nil {
			Log.Printf("MDMLog: Error reading Azure JSON file: %v\n", err)
			return
		}

		var dataHash map[string]interface{}
		if err := json.Unmarshal(fileContent, &dataHash); err != nil {
			Log.Printf("MDMLog: Error parsing JSON file: %v\n", err)
			return
		}

		spClientID, _ := dataHash["aadClientId"].(string)

		if spClientID != "" && strings.ToLower(spClientID) != "msi" {
			useMsi = false
			aadTokenURL := fmt.Sprintf(aadTokenURLTemplate, dataHash["tenantId"].(string))
			parsedTokenURI, err = url.Parse(aadTokenURL)
			if err != nil {
				Log.Printf("MDMLog: Error parsing AAD token URL: %v\n", err)
			}
		} else {
			useMsi = true
			msiEndpoint := fmt.Sprintf(imdsMsiEndpointTemplate, tokenResourceAudience)
			if userAssignedClientID != "" {
				msiEndpoint = fmt.Sprintf(msiEndpointTemplate, userAssignedClientID, tokenResourceURL)
			}
			parsedTokenURI, err = url.Parse(msiEndpoint)
			Log.Printf("MDMLog: MSI Endpoint: %s\n", msiEndpoint)
			Log.Printf("MDMLog: Parsed MSI Endpoint: %v\n", parsedTokenURI)
			if err != nil {
				Log.Printf("MDMLog: Error parsing MSI endpoint URL: %v\n", err)
			}
		}
	}

	processIncomingStream = CheckCustomMetricsAvailability()
	metricsToCollectHash = make(map[string]bool)
	for _, metric := range strings.Split(metricsToCollect, ",") {
		metricsToCollectHash[strings.ToLower(metric)] = true
	}
	Log.Printf("MDMLog: After check_custom_metrics_availability process_incoming_stream is %v", processIncomingStream)

	containerResourceUtilTelemetryTimeTracker = time.Now().Unix()
	pvUsageTelemetryTimeTracker = time.Now().Unix()

	containersExceededCpuThreshold = false
	containersExceededMemRssThreshold = false
	containersExceededMemWorkingSetThreshold = false
	pvExceededUsageThreshold = false

	if processIncomingStream {
		cpuCapacity = 0.0
		cpuAllocatable = 0.0
		memoryCapacity = 0.0
		memoryAllocatable = 0.0
		ensureCPUMemoryCapacityAndAllocatableSet()
		containerCpuLimitHash = make(map[string]float64)
		containerMemoryLimitHash = make(map[string]float64)
		containerResourceDimensionHash = make(map[string]string)
		metricsThresholdHash = GetContainerResourceUtilizationThresholds()
	}
}

func PostToMDM(records []*GenericMetricTemplate) error {
	flushMDMExceptionTelemetry()

	// Check conditions for posting data
	now := time.Now()
	if (!firstPostAttemptMade || now.After(lastPostAttemptTime.Add(retryMDMPostWaitMinutes*time.Minute))) && canSendDataToMDM {
		var postBody []string
		// Assuming chunk is a type that can range over records (implementation depends on your data structure)
		for _, record := range records {
			jsonRecord, err := json.Marshal(record) // Assuming record can be marshalled to JSON
			if err != nil {
				return err
			}
			postBody = append(postBody, string(jsonRecord))
		}

		// Batch processing
		for count := len(postBody); count > 0; {
			currentBatchSize := math.Min(float64(count), float64(recordBatchSize))
			currentBatch := postBody[:int(currentBatchSize)]
			postBody = postBody[int(currentBatchSize):]
			count -= int(currentBatchSize)

			err := PostToMDMHelper(currentBatch)
			if err != nil {
				return err // Handle or log the error as appropriate
			}
		}
	} else {
		if !canSendDataToMDM {
			Log.Printf("MDMLog: Cannot send data to MDM since all required conditions were not met")
		} else {
			timeSinceLastAttempt := now.Sub(lastPostAttemptTime).Minutes()
			Log.Printf("MDMLog: Last Failed POST attempt to MDM was made %.1f min ago. This is less than the current retry threshold of %d min. NO-OP", timeSinceLastAttempt, retryMDMPostWaitMinutes)
		}
	}

	return nil
}

func PostToMDMHelper(batch []string) error {
	var access_token string
	if isArcK8sCluster {
		if isAADMSIAuth && !isWindows {
			access_token = getAccessToken()
		} else {
			if clusterIdentity == nil {
				clusterIdentity = lib.NewArcK8sClusterIdentity()
			}
			var err error
			access_token, err = clusterIdentity.GetClusterIdentityToken()
			if err != nil {
				return err
			}
		}
	} else {
		access_token = getAccessToken()
	}

	var httpClient *http.Client

	if proxyEndpoint == "" {
		httpClient = &http.Client{}
	} else {
		aksResourceID := os.Getenv("AKS_RESOURCE_ID")
		Log.Printf("MDMLog: Proxy configured on this cluster: %s\n", aksResourceID)
		proxyURL, err := url.Parse(proxyEndpoint)
		if err != nil {
			Log.Printf("MDMLog: Error parsing proxy URL: %v\n", err)
			return err
		}
		httpClient = &http.Client{
			Transport: &http.Transport{
				Proxy: http.ProxyURL(proxyURL),
			},
		}
	}

	httpClient.Transport = &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	requestId := uuid.New().String()
	postBody := strings.Join(batch, "\n")
	requestSizeKB := len(postBody) / 1024
	request, err := http.NewRequest("POST", postRequestURI.String(), bytes.NewBuffer([]byte(postBody)))
	if err != nil {
		Log.Printf("MDMLog: Error creating new request: %v", err)
		return err
	}
	request.Header.Set("Content-Type", "application/x-ndjson")
	request.Header.Set("Authorization", "Bearer "+access_token)
	request.Header.Set("x-request-id", requestId)

	Log.Printf("MDMLog: REQUEST BODY SIZE %d KB for requestId: %s\n", requestSizeKB, requestId)

	response, err := httpClient.Do(request)
	if err != nil {
		Log.Printf("MDMLog: Error sending request: %v", err)
		handleError(err, response, requestId)
		return err
	}
	defer response.Body.Close()
	Log.Printf("MDMLog: HTTP Post Response Code: %d for requestId: %s\n", response.StatusCode, requestId)
	if lastTelemetrySentTime.IsZero() || lastTelemetrySentTime.Add(60*time.Minute).Before(time.Now()) {
		lib.SendCustomEvent("AKSCustomMetricsMDMSendSuccessful", nil)
		lastTelemetrySentTime = time.Now()
	}

	return nil
}

func handleError(err error, response *http.Response, requestId string) {
	if response != nil && response.Body != nil {
		bodyBytes, _ := ioutil.ReadAll(response.Body)
		Log.Printf("MDMLog: Failed to Post Metrics to MDM for requestId: %s, exception: %v, Response.body: %s", requestId, err, string(bodyBytes))
	} else {
		Log.Printf("MDMLog: Failed to Post Metrics to MDM for requestId: %s, exception: %v", requestId, err)
	}
	stackTrace := debug.Stack()
	Log.Printf("MDMLog: %s\n", string(stackTrace))

	if response != nil {
		statusCode := response.StatusCode
		switch {
		case statusCode == http.StatusForbidden:
			Log.Printf("MDMLog: Response Code %d for requestId: %s, Updating last post attempt time", statusCode, requestId)
			lastPostAttemptTime = time.Now()
			firstPostAttemptMade = true
		case statusCode >= 400 && statusCode < 500:
			Log.Printf("MDMLog: Non-retryable HTTPClientException when POSTing Metrics to MDM for requestId: %s, exception: %v, Response: %v", requestId, err, response)
		default:
			Log.Printf("MDMLog: HTTPServerException when POSTing Metrics to MDM for requestId: %s, exception: %v, Response: %v", requestId, err, response)
		}
	}

	exceptionAggregator(err)

	// Additional logic for handling Errno::ETIMEDOUT and generic exceptions
	if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
		Log.Printf("MDMLog: Timed out when POSTing Metrics to MDM for requestId: %s, exception: %v", requestId, err)
		stackTrace := debug.Stack()
		Log.Printf("MDMLog: %s\n", string(stackTrace))
	} else if err != nil {
		Log.Printf("MDMLog: Exception POSTing Metrics to MDM for requestId: %s, exception: %v", requestId, err)
		stackTrace := debug.Stack()
		Log.Printf("MDMLog: %s\n", string(stackTrace))
	}

}

func exceptionAggregator(err error) {
	if err != nil {
		exceptionKey := err.Error()
		mdmExceptionsHash[exceptionKey]++
		mdmExceptionsCount++
	}
}

func getAccessToken() string {
	var accessToken string
	var err error
	var retries int = 0
	for ; retries < 2; retries++ {
		accessToken, err = getAccessTokenHelper()
		if err != nil {
			Log.Printf("MDMLog: Error getting access token: %v\n", err)
			Log.Printf("MDMLog: Retrying request to get token - retry number: %d\n", retries)
			time.Sleep(time.Duration(retries) * time.Second)
			continue
		}
	}
	if err != nil && retries >= 2 {
		getAccessTokenBackoffExpiry = time.Now().Add(tokenRefreshBackOffInterval)
		Log.Printf("MDMLog: getAccessTokenBackoffExpiry set to: %s\n", getAccessTokenBackoffExpiry)
		lib.SendExceptionTelemetry(err.Error(), map[string]string{"FeatureArea": "MDM"})
	}
	return accessToken
}

func getAccessTokenHelper() (token string, err error) {
	if !time.Now().After(getAccessTokenBackoffExpiry) {
		return cachedAccessToken, nil
	}

	var httpAccessToken *http.Client
	var tokenRequest *http.Request
	properties := map[string]string{}
	if cachedAccessToken == "" || time.Now().Add(5*time.Minute).After(tokenExpiryTime) {
		Log.Printf("MDMLog: Refreshing access token for out_mdm plugin..")
		if isAADMSIAuth {
			properties["isMSI"] = "true"
		}
		if isAADMSIAuth && isWindows {
			Log.Printf("MDMLog: Reading the token from IMDS token file since it's Windows..")
			if tokenContent, err := ioutil.ReadFile("c:/etc/imds-access-token/token"); err == nil {
				var parsedJson map[string]interface{}
				if err := json.Unmarshal(tokenContent, &parsedJson); err == nil {
					tokenExpiryTime = time.Now().Add(tokenRefreshBackOffInterval)
					cachedAccessToken = parsedJson["access_token"].(string)
					Log.Printf("MDMLog: Successfully got access token")
					lib.SendCustomEvent("AKSCustomMetricsMDMToken-MSI", properties)
				} else {
					Log.Printf("MDMLog: Error parsing the token file content: ", err)
					return "", err
				}
			} else {
				Log.Printf("MDMLog: either MSI Token file path doesn't exist or not readable: ", err)
				return "", err
			}
		} else {
			if useMsi {
				Log.Printf("MDMLog: Using MSI to get the token to post MDM data")
				lib.SendCustomEvent("AKSCustomMetricsMDMToken-MSI", properties)

				httpAccessToken = &http.Client{}
				tokenRequest, err = http.NewRequest("GET", parsedTokenURI.String(), nil)
				if err != nil {
					Log.Printf("MDMLog: Error creating request: %v\n", err)
					return
				}
				tokenRequest.Header.Set("Metadata", "true")
			} else {
				Log.Printf("MDMLog: Using SP to get the token to post MDM data")
				lib.SendCustomEvent("AKSCustomMetricsMDMToken-SP", properties)

				httpAccessToken = &http.Client{Transport: &http.Transport{
					TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
				}}
				formData := url.Values{
					"grant_type":    {grantType},
					"client_id":     {dataHash["aadClientId"].(string)},
					"client_secret": {dataHash["aadClientSecret"].(string)},
					"resource":      {tokenResourceURL},
				}
				tokenRequest, err = http.NewRequest("POST", parsedTokenURI.String(), bytes.NewBufferString(formData.Encode()))
				if err != nil {
					Log.Printf("MDMLog: Error creating request: %v\n", err)
					return
				}
				tokenRequest.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			}

			Log.Printf("MDMLog: Making request to get token..")
			tokenResponse, err := httpAccessToken.Do(tokenRequest)
			if err != nil {
				Log.Printf("MDMLog: Error sending request: %v\n", err)
				return "", err
			}
			defer tokenResponse.Body.Close()

			responseBody, err := ioutil.ReadAll(tokenResponse.Body)
			if err != nil {
				Log.Printf("MDMLog: Error reading response body: %v\n", err)
				return "", err
			}

			var parsedJSON map[string]interface{}
			err = json.Unmarshal(responseBody, &parsedJSON)
			if err != nil {
				Log.Printf("MDMLog: Error parsing JSON response: %v\n", err)
				return "", err
			}

			if accessToken, ok := parsedJSON["access_token"].(string); ok {
				cachedAccessToken = accessToken
				tokenExpiryTime = time.Now().Add(tokenRefreshBackOffInterval)
				Log.Printf("MDMLog: Successfully got access token")
			} else {
				Log.Printf("MDMLog: Error: access token not found in response")
				return "", errors.New("access token not found in response")
			}
		}

	}
	return cachedAccessToken, nil
}

func flushMDMExceptionTelemetry() {
	timeDifference := math.Abs(float64(time.Now().Unix()) - float64(mdmExceptionTelemetryTimeTracker))
	timeDifferenceInMinutes := timeDifference / 60
	if timeDifferenceInMinutes > MDM_EXCEPTIONS_METRIC_FLUSH_INTERVAL {
		telemetryProperties := map[string]string{}
		telemetryProperties["ExceptionsHashForFlushInterval"] = fmt.Sprintf("%v", mdmExceptionsHash)
		telemetryProperties["FlushInterval"] = fmt.Sprintf("%v", MDM_EXCEPTIONS_METRIC_FLUSH_INTERVAL)
		lib.SendMetricTelemetry(MDMExceptionTelemetryMetric, float64(mdmExceptionsCount), telemetryProperties)
		mdmExceptionsCount = 0
		mdmExceptionsHash = make(map[string]int)
		mdmExceptionTelemetryTimeTracker = time.Now().Unix()
	}
}

func PostCAdvisorMetricsToMDM(records []map[string]interface{}) int {
	Log.Printf("MDMLog: PostCAdvisorMetricsToMDM::Info:PostCAdvisorMetricsToMDM starting")
	if (records == nil) || !(len(records) > 0) {
		Log.Printf("MDMLog: PostCAdvisorMetricsToMDM::Error:no records")
		return output.FLB_OK
	}

	defer func() {
		if r := recover(); r != nil {
			stacktrace := debug.Stack()
			Log.Printf("MDMLog: Error processing cadvisor metrics records: %v, stacktrace: %v", r, stacktrace)
			lib.SendExceptionTelemetry(fmt.Sprintf("Error: %v, stackTrace: %v", r, stacktrace), nil)
		}
	}()

	ensureCPUMemoryCapacityAndAllocatableSet()
	if processIncomingStream {
		var err error
		containerCpuLimitHash, containerMemoryLimitHash, containerResourceDimensionHash, err = GetAllContainerLimits()
		if err != nil {
			Log.Printf("MDMLog: Error getting container limits: %v", err)
			lib.SendExceptionTelemetry(err.Error(), nil)
		}
	}

	var mdmMetrics []*GenericMetricTemplate
	for _, message := range records {
		filtered_records, err := filterCAdvisor2MDM(message)
		if err != nil {
			message := fmt.Sprintf("PostCAdvisorMetricsToMDM::Error:when processing cadvisor metric %q", err)
			Log.Printf(message)
			lib.SendException(message)
		}
		mdmMetrics = append(mdmMetrics, filtered_records...)
	}
	err := PostToMDM(mdmMetrics)
	if err != nil {
		Log.Printf("MDMLog: PostCAdvisorMetricsToMDM::Error:Failed to post to MDM %v", err)
		return output.FLB_RETRY
	}

	return output.FLB_OK
}

func filterCAdvisor2MDM(record map[string]interface{}) ([]*GenericMetricTemplate, error) {
	if !processIncomingStream {
		return nil, nil
	}

	if nameValue, ok := record["Name"]; ok {
		if strings.EqualFold(nameValue.(string), PVUsedBytes) {
			return filterPVInsightsMetrics(record)
		}
	}

	objectName := record["ObjectName"].(string)

	var collections []map[string]interface{}
	jsonCollections, ok := record["json_Collections"].(string)
	if !ok {
		log.Fatalf("Error parsing json_Collections: expected string, got %T", record["json_Collections"])
	}
	err := json.Unmarshal([]byte(jsonCollections), &collections)
	if err != nil {
		log.Fatalf("Error parsing json_Collections: %v", err)
	}

	counterName := collections[0]["CounterName"].(string)

	percentageMetricValue := 0.0
	allocatablePercentageMetricValue := 0.0

	if objectName == ObjectNameK8SNode && metricsToCollectHash[strings.ToLower(counterName)] {
		Log.Printf("MDMLog: Processing node metric: %s", counterName)
		var metricName string
		metricValue := collections[0]["Value"].(float64)
		if counterName == CPUUsageNanoCores {
			metricName = CPUUsageMilliCores
			metricValue = metricValue / 1000000
			var targetNodeCpuCapacityMC float64
			var targetNodeCpuAllocatableMc float64
			// TODO: is the below needed? earlier this replicaset check was to get windows ds data

			// if controllerType == "replicaset" {
			// 	targetNodeCpuCapacityMC =  nil
			// 	targetNodeCpuAllocatableMc = 0.0
			// } else {
			// 	targetNodeCpuCapacityMC = cpuCapacity
			// 	targetNodeCpuAllocatableMc = cpuAllocatable
			// }
			targetNodeCpuCapacityMC = cpuCapacity
			targetNodeCpuAllocatableMc = cpuAllocatable

			Log.Printf("MDMLog: Metric value: %f CPU Capacity %f CPU Allocatable %f", metricValue, targetNodeCpuCapacityMC, targetNodeCpuAllocatableMc)
			if targetNodeCpuCapacityMC != 0.0 {
				percentageMetricValue = (metricValue / targetNodeCpuCapacityMC) * 100
			}
			if targetNodeCpuAllocatableMc != 0.0 {
				allocatablePercentageMetricValue = (metricValue / targetNodeCpuAllocatableMc) * 100
			}
		}

		if strings.HasPrefix(counterName, "memory") {
			metricName = counterName
			metricValue := collections[0]["Value"].(float64)
			var targetNodeMemoryCapacity float64
			var targetNodeMemoryAllocatable float64
			// TODO: is the below needed? earlier this replicaset check was to get windows ds data

			// if controllerType == "replicaset" {
			// 	targetNodeMemoryCapacity = nil
			// 	targetNodeMemoryAllocatable = 0.0
			// } else {
			// 	targetNodeMemoryCapacity = memoryCapacity
			// 	targetNodeMemoryAllocatable = memoryAllocatable
			// }
			targetNodeMemoryCapacity = memoryCapacity
			targetNodeMemoryAllocatable = memoryAllocatable

			Log.Printf("MDMLog: Metric_value: %f Memory Capacity %f Memory Allocatable %f", metricValue, targetNodeMemoryCapacity, targetNodeMemoryAllocatable)

			if targetNodeMemoryCapacity != 0.0 {
				percentageMetricValue = (metricValue / targetNodeMemoryCapacity) * 100
			}
			if targetNodeMemoryAllocatable != 0.0 {
				allocatablePercentageMetricValue = (metricValue / targetNodeMemoryAllocatable) * 100
			}
		}

		Log.Printf("MDMLog: percentage_metric_value for metric: %s for instance: %s percentage: %f allocatable_percentage: %f", metricName, record["Host"], percentageMetricValue, allocatablePercentageMetricValue)

		if percentageMetricValue > 100.0 {
			telemetryProperties := map[string]string{}
			telemetryProperties["Computer"] = record["Host"].(string)
			telemetryProperties["MetricName"] = metricName
			telemetryProperties["MetricPercentageValue"] = strconv.FormatFloat(percentageMetricValue, 'f', -1, 64)
			lib.SendCustomEvent("ErrorPercentageOutOfBounds", telemetryProperties)
		}

		if allocatablePercentageMetricValue > 100.0 {
			telemetryProperties := map[string]string{}
			telemetryProperties["Computer"] = record["Host"].(string)
			telemetryProperties["MetricName"] = metricName
			telemetryProperties["MetricAllocatablePercentageValue"] = strconv.FormatFloat(allocatablePercentageMetricValue, 'f', -1, 64)
			lib.SendCustomEvent("ErrorPercentageOutOfBounds", telemetryProperties)
		}

		return GetNodeResourceMetricRecords(record, metricName, metricValue, percentageMetricValue, allocatablePercentageMetricValue)
	} else if objectName == ObjectNameK8SContainer && metricsToCollectHash[strings.ToLower(counterName)] {
		Log.Printf("MDMLog: Processing container metric: %s", counterName)
		metricValue := collections[0]["Value"].(float64)
		instanceName := record["InstanceName"].(string)
		metricName := counterName
		// Using node cpu capacity in the absence of container cpu capacity since the container will end up using the
		// node's capacity in this case. Converting this to nanocores for computation purposes, since this is in millicores
		containerCpuLimit := cpuCapacity * 1000000
		containerMemoryLimit := memoryCapacity

		if counterName == CPUUsageNanoCores {
			if instanceName != "" {
				if val, ok := containerCpuLimitHash[instanceName]; ok {
					containerCpuLimit = val
				}
			}

			// Checking if KubernetesApiClient ran into error while getting the numeric value or if we failed to get the limit
			if containerCpuLimit != 0.0 {
				percentageMetricValue = (metricValue / containerCpuLimit) * 100
			}
		} else if strings.HasPrefix(counterName, "memory") {
			if instanceName != "" {
				if val, ok := containerMemoryLimitHash[instanceName]; ok {
					containerMemoryLimit = val
				}
			}

			// Checking if KubernetesApiClient ran into error while getting the numeric value or if we failed to get the limit
			if containerMemoryLimit != 0.0 {
				percentageMetricValue = (metricValue / containerMemoryLimit) * 100
			}
		}

		Log.Printf("MDMLog: percentage_metric_value for metric: %s for instance: %s percentage: %f", metricName, instanceName, percentageMetricValue)
		Log.Printf("MDMLog: metric_threshold_hash for %s: %f", metricName, metricsThresholdHash[metricName])
		thresholdPercentage := metricsThresholdHash[metricName]

		flushMetricTelemetry()
		if percentageMetricValue >= thresholdPercentage {
			setThresholdExceededTelemetry(metricName)
			return GetContainerResourceUtilMetricRecords(record["Timestamp"].(string), metricName, percentageMetricValue, containerResourceDimensionHash[instanceName], thresholdPercentage, false)
		} else {
			return nil, nil
		}
	} else {
		return nil, nil
	}
}

func filterPVInsightsMetrics(record map[string]interface{}) ([]*GenericMetricTemplate, error) {
	mdmMetrics := []*GenericMetricTemplate{}

	if record["Name"] == PVUsedBytes && metricsToCollectHash[strings.ToLower(record["Name"].(string))] {
		metricName := record["Name"].(string)
		usage := record["Value"].(float64)

		var tags map[string]string
		tagsBytes, ok := record["Tags"].(string)
		if !ok {
			return nil, errors.New("error getting tags")
		}
		tagsBytesSlice := []byte(tagsBytes)
		err := json.Unmarshal(tagsBytesSlice, &tags)
		if err != nil {
			Log.Printf("MDMLog: Error parsing tags: %v", err)
			lib.SendExceptionTelemetry(err.Error(), nil)
			return nil, err
		}

		fCapacity, _ := strconv.ParseFloat(tags[InsightsMetricsTagsPVCapacityBytes], 64)

		percentageMetricValue := 0.0
		if fCapacity != 0.0 {
			percentageMetricValue = (usage / fCapacity) * 100
		}
		Log.Printf("MDMLog: percentage metric value for %s is %f", metricName, percentageMetricValue)
		Log.Printf("MDMLog: metricsThresholdHash for %s is %f", metricName, metricsThresholdHash[metricName])

		computer := record["Computer"].(string)
		resourceDimensions := tags
		thresholdPercentage := metricsThresholdHash[metricName]

		flushMetricTelemetry()

		collectionTime := record["CollectionTime"].(string)
		if percentageMetricValue >= thresholdPercentage {
			setThresholdExceededTelemetry(metricName)
			return GetPVResourceUtilMetricRecords(collectionTime, metricName, computer, percentageMetricValue, resourceDimensions, thresholdPercentage, false)
		} else {
			return nil, nil
		}
	}

	return mdmMetrics, nil

}

func setThresholdExceededTelemetry(metricName string) {
	switch metricName {
	case CPUUsageNanoCores:
		containersExceededCpuThreshold = true
	case MemoryRssBytes:
		containersExceededMemRssThreshold = true
	case MemoryWorkingSetBytes:
		containersExceededMemWorkingSetThreshold = true
	case PVUsedBytes:
		pvExceededUsageThreshold = true
	}
}

func flushMetricTelemetry() {
	timeDifference := math.Abs(float64(time.Now().Unix()) - float64(containerResourceUtilTelemetryTimeTracker))
	timeDifferenceInMinutes := timeDifference / 60
	if timeDifferenceInMinutes > TelemetryFlushIntervalInMinutes {
		properties := map[string]string{}
		properties["CpuThresholdPercentage"] = strconv.FormatFloat(metricsThresholdHash[CPUUsageNanoCores], 'f', -1, 64)
		properties["MemoryRssThresholdPercentage"] = strconv.FormatFloat(metricsThresholdHash[MemoryRssBytes], 'f', -1, 64)
		properties["MemoryWorkingSetThresholdPercentage"] = strconv.FormatFloat(metricsThresholdHash[MemoryWorkingSetBytes], 'f', -1, 64)
		// Keeping track of any containers that have exceeded threshold in the last flush interval
		properties["CpuThresholdExceededInLastFlushInterval"] = strconv.FormatBool(containersExceededCpuThreshold)
		properties["MemRssThresholdExceededInLastFlushInterval"] = strconv.FormatBool(containersExceededMemRssThreshold)
		properties["MemWSetThresholdExceededInLastFlushInterval"] = strconv.FormatBool(containersExceededMemWorkingSetThreshold)
		lib.SendCustomEvent(ContainerResourceUtilHeartBeatEvent, properties)
		containersExceededCpuThreshold = false
		containersExceededMemRssThreshold = false
		containersExceededMemWorkingSetThreshold = false
		containerResourceUtilTelemetryTimeTracker = time.Now().Unix()
	}

	if !isWindows {
		timeDifference := math.Abs(float64(time.Now().Unix()) - float64(pvUsageTelemetryTimeTracker))
		timeDifferenceInMinutes := timeDifference / 60
		if timeDifferenceInMinutes > TelemetryFlushIntervalInMinutes {
			properties := map[string]string{}
			properties["PVUsageThresholdPercentage"] = strconv.FormatFloat(metricsThresholdHash[PVUsedBytes], 'f', -1, 64)
			properties["PVUsageThresholdExceededInLastFlushInterval"] = strconv.FormatBool(pvExceededUsageThreshold)
			lib.SendCustomEvent(PvUsageHeartBeatEvent, properties)
			pvExceededUsageThreshold = false
			pvUsageTelemetryTimeTracker = time.Now().Unix()
		}
	}
}

func ensureCPUMemoryCapacityAndAllocatableSet() {
	if controllerType == "daemonset" {
		if cpuCapacity != 0.0 && memoryCapacity != 0.0 && cpuAllocatable != 0.0 && memoryAllocatable != 0.0 {
			Log.Printf("MDMLog: CPU And Memory Capacity are already set and their values are as follows cpu_capacity : %f, memory_capacity: %f", cpuCapacity, memoryCapacity)
			Log.Printf("MDMLog: CPU And Memory Allocatable are already set and their values are as follows cpu_allocatable : %f, memory_allocatable: %f", cpuAllocatable, memoryAllocatable)
			return
		}
	}

	if controllerType == "daemonset" {
		var err error
		cpuCapacity, memoryCapacity, err = GetNodeCapacity()
		if err != nil {
			Log.Printf("MDMLog: Error getting capacity_from_kubelet: cpu_capacity and memory_capacity")
			lib.SendExceptionTelemetry(err.Error(), nil)
			return
		}
		cpuAllocatable, memoryAllocatable, err = GetNodeAllocatable(cpuCapacity, memoryCapacity)
		if err != nil {
			Log.Printf("MDMLog: Error getting allocatable_from_kubelet: cpu_allocatable and memory_allocatable")
			lib.SendExceptionTelemetry(err.Error(), nil)
			return
		}
	}

}

func PostTelegrafMetricsToMDM(telegrafRecords []map[interface{}]interface{}) int {
	Log.Printf("MDMLog: PostTelegrafMetricsToMDM::Info:PostTelegrafMetricsToMDM starting")
	if (telegrafRecords == nil) || !(len(telegrafRecords) > 0) {
		Log.Printf("MDMLog: PostTelegrafMetricsToMDM::Error:no timeseries to derive")
		return output.FLB_OK
	}

	defer func() {
		if r := recover(); r != nil {
			stacktrace := debug.Stack()
			Log.Printf("MDMLog: Error processing telegraf MDM metrics records: %v, stacktrace: %v", r, stacktrace)
			lib.SendExceptionTelemetry(fmt.Sprintf("Error: %v, stackTrace: %v", r, stacktrace), nil)
		}
	}()

	processIncomingStream := CheckCustomMetricsAvailability()

	if !processIncomingStream {
		Log.Printf("MDMLog: PostTelegrafMetricsToMDM::Info:Custom metrics is not enabled for this workspace. Skipping processing of incoming stream")
		return output.FLB_OK
	}

	var mdmMetrics []*GenericMetricTemplate

	for _, record := range telegrafRecords {
		filtered_records, err := filterTelegraf2MDM(record)
		if err != nil {
			message := fmt.Sprintf("PostTelegrafMetricsToMDM::Error:when processing telegraf metric %q", err)
			Log.Printf(message)
			lib.SendException(message)
		}
		mdmMetrics = append(mdmMetrics, filtered_records...)
	}

	err := PostToMDM(mdmMetrics)
	if err != nil {
		Log.Printf("MDMLog: PostTelegrafMetricsToMDM::Error:Failed to post to MDM %v", err)
		return output.FLB_RETRY
	}

	return output.FLB_OK
}

func filterTelegraf2MDM(record map[interface{}]interface{}) ([]*GenericMetricTemplate, error) {
	convertedRecord := convertRecord(record)
	if strings.EqualFold(convertedRecord["name"].(string), TelegrafDiskMetrics) {
		return GetDiskUsageMetricRecords(convertedRecord)
	} else {
		return GetMetricRecords(convertedRecord)
	}
}

func convertRecord(record map[interface{}]interface{}) map[string]interface{} {
	converted := make(map[string]interface{})

	for key, value := range record {
		switch key := key.(type) {
		case string:
			switch v := value.(type) {
			case []uint8: // Assuming incoming byte slices are of type []uint8
				// Convert byte slice to string
				converted[key] = string(v)
			case map[interface{}]interface{}:
				// Recursively handle nested maps
				converted[key] = convertRecord(v)
			default:
				// Leave other types as-is
				converted[key] = v
			}
		}
	}

	return converted
}

func toStringMap(record map[interface{}]interface{}) map[string]interface{} {
	tag := record["tag"].([]byte)
	mp := make(map[string]interface{})
	mp["tag"] = string(tag)
	mp["messages"] = []map[string]interface{}{}
	message := record["messages"].([]interface{})
	for _, entry := range message {
		newEntry := entry.(map[interface{}]interface{})
		m := make(map[string]interface{})
		for k, v := range newEntry {
			switch t := v.(type) {
			case []byte:
				m[k.(string)] = string(t)
			default:
				m[k.(string)] = v
			}
		}
		mp["messages"] = append(mp["messages"].([]map[string]interface{}), m)
	}

	return mp
}
